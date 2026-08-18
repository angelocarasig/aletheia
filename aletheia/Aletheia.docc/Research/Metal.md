# Metal Compute

The standard for using Metal in this app, researched for the recommender's embedding block and
then not needed - the same block was parallelised across CPU cores instead, and the app confirmed
it will never need a batch/library-wide scoring path, which removed both reasons Metal looked
attractive. Nothing in the app uses Metal today; **the CPU path is the only implementation.** Kept
because the research doesn't rot for about a year, and the day something genuinely needs the GPU
it starts from a written standard instead of sample code of unknown vintage.

Compute only - there's no graphics work in this app.

## Prerequisite: the toolchain is a separate download

```
$ xcrun -sdk iphoneos metal --version
error: cannot execute tool 'metal' due to missing Metal Toolchain;
       use: xcodebuild -downloadComponent MetalToolchain
```

The Metal compiler is an optional ~700 MB component since Xcode 26. Adding the first `.metal` file
fails the build until it's installed - on any machine, including CI.

## The rules

1. A `.metal` file in the app target is the standard - the synchronized root group classifies it
   by extension with no `project.pbxproj` edit, producing `default.metallib` in the app bundle.
2. Load with the throwing variant. `makeDefaultLibrary()` returns `nil` with no error object;
   `try makeDefaultLibrary(bundle: .main)` throws something diagnosable. Same for
   `makeFunction(name:)`, which returns `nil` on a typo and tells you nothing.
3. Long-lived objects (device, queue, library, function, pipeline) are built once, at init, off
   the main actor. The pipeline is the expensive one - it compiles IR to a GPU binary.
4. An actor is the right home. `MTLDevice`, `MTLCommandQueue`, `MTLComputePipelineState`,
   `MTLLibrary`, `MTLFunction`, `MTLEvent`, and `MTLFence` are `NS_SWIFT_SENDABLE` as of the iOS 26
   SDK. `MTLBuffer`, `MTLCommandBuffer`, and `MTLComputeCommandEncoder` are not - created and
   consumed inside one actor-isolated call, never crossing an isolation boundary.
5. Capability is decided once at init and never re-derived per call - cache `supportsFamily`,
   `maxBufferLength`, and each pipeline's thread limits. Any setup failure latches the CPU path on
   for the process.
6. Per call, guard sizes only: buffer length against `maxBufferLength`, threadgroup size against
   the cached pipeline limit, no zero grid dimension.
7. `await commandBuffer.completed()`, never `waitUntilCompleted()` - the latter is unavailable from
   async contexts, and blocking a cooperative-pool thread on GPU completion deadlocks.
8. Read results only after completion - `contents()` before that returns garbage silently. No
   `synchronize`/`didModifyRange` on iOS; both are macOS managed-mode only.
9. **The CPU path is the reference implementation, not the fallback.** It's what the simulator
   runs, what a backgrounded app runs, and what the GPU result is diffed against.

`maxTotalThreadsPerThreadgroup` is a property of the pipeline, not the device - register pressure
lowers it per kernel and per GPU. Exceeding it is an assertion and a process abort, not a
catchable throw. Write the `if (gid >= count) return;` guard in the kernel regardless - a fallback
dispatch shape over-dispatches and needs it.

## The simulator is not a device, in both directions

| | simulator | device (A13+) |
|---|---|---|
| `supportsFamily` | apple1, apple2, common1 only | apple1-9, common1-3, metal3, metal4 |
| `hasUnifiedMemory` | false | true |
| `maxBufferLength` | 256 MB | 1-2 GB+ |
| `maxThreadsPerThreadgroup` | 512 | 1024 |
| Metal 4 headers | empty stubs, doesn't compile | present |

Stricter than a device: `dispatchThreads` is rejected by API validation on a shape every real
device accepts, since every iOS 26 iPhone is A13/apple6 or better. Constant buffer offsets need
256-byte alignment in the simulator; iOS requires 4. Don't use the simulator as a smoke test for
either.

Looser than a device, the dangerous direction: it accepts a threadgroup size a real device rejects;
it doesn't enforce `bytesNoCopy` page alignment or length rounding; it runs MSL features its
declared feature level says it lacks. One hard crash unique to it: `makeBuffer(bytesNoCopy:)` over
`malloc`'d memory aborts the process in the simulator, because the simulator ferries buffer memory
to the host over XPC shared memory. `mmap`/`vm_allocate` are fine everywhere.

## Errors and fallback

Nothing fails loudly by default. With validation off, a shader writing past the end of a buffer, a
buffer binding never set then read, a zero grid dimension, and an oversized threadgroup all report
`.completed` with no error. Garbage output is the only symptom.

Turn Metal API Validation on in the scheme and leave it on - it catches most of those. Shader
Validation catches out-of-bounds access but must never ship: it's expensive and it changes the
values `maxTotalThreadsPerThreadgroup` and `threadExecutionWidth` return, so never size a dispatch
from a value read while it's enabled. Ship `errorOptions = .encoderExecutionStatus` with labelled
encoders - low overhead, and the only thing that says which dispatch faulted on someone else's
phone.

`notPermitted` is backgrounding, and it's the case to design for rather than an edge - iOS
restricts a backgrounded app's GPU access, and it self-heals on foreground. `timeout`, `pageFault`,
`internal`, and `accessRevoked` should latch the CPU path on for the process - faults cascade, and
a burst is not retryable even though a single fault is. Never `abort()` on a command buffer error;
the documented shape is a recoverable `status == .error`. There's no published GPU watchdog
timeout and no way to cancel dispatched GPU work - dispatch granularity, chosen before commit, is
the only control.

## Memory

GPU allocations count against the app's memory footprint and jetsam - there's no separate VRAM
pool on Apple silicon. The word that matters is *accessed*: an untouched mmap costs nothing, a
CPU-read of a file-backed mapping costs nothing (clean pages), wrapping a mapping in an
`MTLBuffer(noCopy:)` costs nothing, but writing to a shared buffer charges immediately. A
read-only file-backed mapping is the cheap way to hold a large model.

`makeBuffer(bytesNoCopy:)` needs a page-aligned pointer, a page-aligned length, and a single VM
region - `mmap` gives the alignment for free, only the length needs rounding. Page size on arm64
iOS is 16384, not 4096, and it's a runtime variable (`sysconf(_SC_PAGESIZE)`), never hardcode it.
`storageModeManaged`/`didModifyRange` don't exist on iOS; the valid storage modes for compute are
`shared` and `private`.

## Deprecations to not copy from older sample code

`MTLCompileOptions.fastMathEnabled` -> `mathMode`. `MTLFeatureSet`/`supportsFeatureSet(_:)` ->
`supportsFamily`. `MTLArgument`/`reflection.arguments` -> `MTLBinding`/`bindings`.
`makeLibrary(filepath:)` -> `makeLibrary(URL:)`. `MTLCommandBufferError.blacklisted` ->
`.accessRevoked`. Nothing on the classic compute path is deprecated at iOS 26 - MPS itself is not
deprecated, only MPS ray tracing.

Metal 4 is worth skipping here: opt-in, requires A14 while this app's floor is A13 (so a classic
fallback is needed regardless), absent from the simulator SDK, and shader debugging still missing
in Xcode 26.

## Writing a kernel

Measured guidance from the recommender's case - a large int8 matrix dotted against one row. One
thread per output row beat a simdgroup-per-row reduction at this row width. `char4`, not
`packed_char4`, only when the row stride guarantees 4-byte alignment. There's no integer `dot()` in
MSL. MSL does no integer promotion for vector operands, which is the highest-value thing to check
in review - `char4 p = r[i] * s[i]` is 8-bit componentwise arithmetic that silently wraps;
`int4(r[i]) * int4(s[i])` is correct. Integer accumulation is exact and order-independent, so a
GPU result can match a CPU `Int32` reference bit for bit - prefer emitting `int` and applying any
float scale on the consumer side, so the kernel executes no floating-point instruction at all.
`simd_sum` is the current reduction primitive if one is needed, not a hand-rolled threadgroup tree.

Before writing a kernel, check whether a framework already does it, and check that it accepts your
data type - for int8, none of `MPSMatrixVectorMultiplication`, `MPSGraph`, BNNS, or Accelerate's
GEMV did.

## Verified wrong

Common, plausible, and false at this SDK: that Metal doesn't work in the simulator (it runs on the
host GPU, stale since 2019); that the simulator's declared feature family tells you what it
actually enforces (wrong in both directions, see above); that running without crashing means the
compute is correct (four separate defects all reported `.completed` with no error); that
`makeCommandBuffer()` returns `nil` when the queue is full (it blocks the calling thread instead -
the symptom is a CPU hang); that GPU memory doesn't count against the app (it does, and jetsam
enforces it); that page alignment on iOS is 4096 (it's 16384, and it's a runtime variable); that
`recommendedMaxWorkingSetSize` is macOS-only (available on iOS since 16); that exceeding
`maxTotalThreadsPerThreadgroup` throws (it asserts and aborts, and the limit is per-pipeline, not
per-device); that MPS is deprecated in iOS 26 (only MPS ray tracing is).

## A SIMD crash that looked like an alignment fault and wasn't

A memory-mapped read through `loadUnaligned(fromByteOffset:as: SIMD16<Int8>.self)` passed every
check in the simulator, including a full fixture-based ranking comparison, and crashed on an arm64
iPhone. The natural diagnosis - misaligned vector load - doesn't survive scrutiny on three
grounds: `loadUnaligned` genuinely guarantees an unaligned load with no alignment assumption
inserted; arm64 doesn't fault on misaligned vector loads at all; and if alignment were the cause it
would crash the x86_64 simulator and pass on device, the exact inverse of what happened.

The cause is unestablished. Candidates, in order of plausibility: a SIGBUS from the mapping itself
(a read straddling the end of the backing file, where `mmap` zero-fills only to the end of the
last page); data protection (an mmap'd file in a protected class becoming unreadable while the
device is locked, which has no simulator equivalent and fits the symptom); or an ordinary
out-of-bounds index whose consequences differ because the page size differs and the simulator has
no jetsam.

Two things worth carrying regardless of the unresolved cause: unaligned SIMD access in Swift is
done with `loadUnaligned` and nothing else (`assumingMemoryBound`, `bindMemory`, and `load(as:)`
all assert alignment to LLVM, and on arm64 they happen to work, which is worse than failing
loudly). And don't trust `load`'s misalignment precondition to catch this class of bug - it's a
debug precondition living in the prebuilt standard library, so it doesn't fire even unoptimized.

## Open

Whether GPU access through a `bytesNoCopy` wrapper dirties file-backed pages is unsettled by any
Apple statement, and it decides whether large-file compute on iOS is footprint-free or
footprint-fatal - one on-device measurement (mmap, wrap, run a kernel that reads all of it, diff
the process's physical footprint) would answer it; a host measurement doesn't transfer, a host
isn't a phone. Whether `PROT_READ`-only mappings are accepted by `makeBuffer(bytesNoCopy:)` is
untested. GPU work from a background task: iOS 26 adds a continued-processing background task type
for GPU work, gated on a capability that's reported false on every device tested so far - assume
GPU compute is unavailable in the background and let the CPU path carry it.
