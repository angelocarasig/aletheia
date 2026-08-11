//
//  NetworkService.swift
//  aletheia
//
//  Created by Angelo Carasig on 4/8/2026.
//

import Foundation

protocol NetworkConfiguration: Sendable {
    func get<Model: Decodable>(url: URL, headers: [String: String]?) async throws -> Model
    func get(url: URL, headers: [String: String]?) async throws -> Data
    func post<Request: Encodable, Response: Decodable>(url: URL, body: Request, headers: [String: String]?) async throws -> Response
    
    // generic
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

extension NetworkConfiguration {
    func get<Model: Decodable>(url: URL) async throws -> Model {
        try await get(url: url, headers: nil)
    }
    
    func get(url: URL) async throws -> Data {
        try await get(url: url, headers: nil)
    }
    
    func post<Request: Encodable, Response: Decodable>(url: URL, body: Request) async throws -> Response {
        try await post(url: url, body: body, headers: nil)
    }
}

final class NetworkService: NetworkConfiguration {
    private let decoder: JSONDecoder
    private let session: URLSession
    private let gate: HostGate

    init(gate: HostGate = HostGate()) {
        self.gate = gate

        // an owned session rather than .shared, which ignores configuration and
        // so cannot carry a resource timeout at all. a caller needing different
        // timings builds its own request and goes through send(_:)
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = Constants.Network.timeout
        configuration.timeoutIntervalForResource = Constants.Network.resourceTimeout
        configuration.httpMaximumConnectionsPerHost = Constants.Network.connectionsPerHost
        self.session = URLSession(configuration: configuration)

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            
            let formatters = [
                NetworkService.isoDateFormatter(),
                NetworkService.millisecondDateFormatter()
            ]
            
            for formatter in formatters {
                if let date = formatter.date(from: dateString) {
                    return date
                }
            }
            
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date string: \(dateString)")
        }
    }
    
    func get<Model: Decodable>(url: URL, headers: [String: String]?) async throws -> Model {
        let data: Data
        let response: URLResponse
        
        do {
            (data, response) = try await makeRequest(url: url, method: "GET", body: nil, headers: headers)
            try handleResponse(response)
        } catch is CancellationError {
            throw CancellationError()
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw NetworkError.cancelled
        } catch let error as NetworkError {
            throw error
        } catch {
            throw NetworkError.failed(error as? URLError ?? URLError(.unknown))
        }
        
        do {
            return try decoder.decode(Model.self, from: data)
        } catch let decodingError as DecodingError {
            throw NetworkError.decoding(type: String(describing: Model.self), error: decodingError)
        }
    }
    
    // overriden function for get calls that expect `Data` returned (typically icons, chapter pages)
    func get(url: URL, headers: [String: String]? = nil) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "GET"
        
        if let headers = headers {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        
        let (data, response) = try await perform(request)
        try handleResponse(response)

        return data  // Return raw, no JSON decoding
    }
    
    func post<Request: Encodable, Response: Decodable>(url: URL, body: Request, headers: [String: String]? = nil) async throws -> Response {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let headers = headers {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        
        do {
            let encoder = JSONEncoder()
            request.httpBody = try encoder.encode(body)
        } catch {
            throw NetworkError.encoding(error)
        }
        
        let (data, response) = try await perform(request)
        try handleResponse(response)

        do {
            return try decoder.decode(Response.self, from: data)
        } catch let decodingError as DecodingError {
            throw NetworkError.decoding(type: String(describing: Response.self), error: decodingError)
        }
    }
    
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await perform(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.failed(URLError(.badServerResponse))
        }
        return (data, httpResponse)
    }

    private func makeRequest(url: URL, method: String, body: Data?, headers: [String: String]?) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let headers = headers {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        if let body = body {
            request.httpBody = body
        }

        return try await perform(request)
    }

    // the one place a request leaves the app: the host gate, the owned session,
    // and the url-error mapping all live here so no path can miss one
    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        // temporary: separates time spent parked at the gate from time spent on
        // the wire. delete with the rest of trackers.timing
        let queued = Date.now
        return try await gate.execute(host: request.url?.host()) { [session] in
            let admitted = Date.now
            defer {
                AppLog.shared.log(
                    "\(request.httpMethod ?? "GET") \(request.url?.host() ?? "?") - gate \(Timing.ms(queued, admitted)), wire \(Timing.ms(admitted))",
                    category: "trackers.timing"
                )
            }

            do {
                return try await session.data(for: request)
            } catch let urlError as URLError {
                switch urlError.code {
                case .cancelled:
                    throw NetworkError.cancelled
                case .notConnectedToInternet:
                    throw NetworkError.offline
                case .timedOut:
                    throw NetworkError.timeout
                default:
                    throw NetworkError.failed(urlError)
                }
            } catch is CancellationError {
                throw NetworkError.cancelled
            } catch {
                throw NetworkError.failed(URLError(.unknown))
            }
        }
    }
    
    private func handleResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.badResponse(status: httpResponse.statusCode, response: httpResponse)
        }
    }
    
    static func isoDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }
    
    static func millisecondDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }
}
