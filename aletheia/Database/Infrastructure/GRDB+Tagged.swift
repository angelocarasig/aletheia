//
//  GRDB+Tagged.swift
//  aletheia
//
//  Created by Angelo Carasig on 4/8/2026.
//

import GRDB
import Tagged

/// https://github.com/groue/GRDB.swift/issues/1435#issuecomment-1740857712

extension Tagged: @retroactive SQLExpressible
where RawValue: SQLExpressible {}

extension Tagged: @retroactive StatementBinding
where RawValue: StatementBinding {}

extension Tagged: @retroactive StatementColumnConvertible
where RawValue: StatementColumnConvertible {}

extension Tagged: @retroactive DatabaseValueConvertible
where RawValue: DatabaseValueConvertible {}
