//
//  NightscoutUtils.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2023-04-09.
//  Copyright © 2023 Jon Fawcett. All rights reserved.
//

import Foundation

class NightscoutUtils {
    enum NightscoutError: Error, LocalizedError {
        case emptyAddress
        case invalidURL
        case networkError
        case siteNotFound
        case invalidToken
        case tokenRequired
        case unknown

        var errorDescription: String? {
            switch self {
            case .emptyAddress:
                return "The address is empty."
            case .invalidURL:
                return "The URL is invalid."
            case .networkError:
                return "A network error occurred."
            case .siteNotFound:
                return "The site was not found."
            case .invalidToken:
                return "The token is invalid."
            case .tokenRequired:
                return "A token is required."
            case .unknown:
                return "An unknown error occurred."
            }
        }
    }

    enum EventType: String {
        case cage = "Site Change"
        case carbsToday = "Carb Correction"
        case sage = "Sensor Start"
        case sgv
        case profile
        case treatments
        case deviceStatus
        case iage = "Insulin Change"

        var endpoint: String {
            switch self {
            case .cage, .carbsToday, .sage, .treatments, .iage:
                return "/api/v1/treatments.json"
            case .sgv:
                return "/api/v1/entries.json"
            case .profile:
                return "/api/v1/profile/current.json"
            case .deviceStatus:
                return "/api/v1/devicestatus.json"
            }
        }
    }
    
    static func executeRequest<T: Decodable>(
        eventType: EventType,
        parameters: [String: String],
        completion: @escaping (Result<T, Error>) -> Void
    ) {
        let baseURL = ObservableUserDefaults.shared.url.value
        let token = UserDefaultsRepository.token.value

        guard let url = NightscoutUtils.constructURL(baseURL: baseURL,
                                                     token: token,
                                                     endpoint: eventType.endpoint,
                                                     parameters: parameters) else {
            DispatchQueue.main.async {
                completion(.failure(NightscoutError.invalidURL))
            }
            return
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        // 👇 Viktigt: snällare nätbeteende i dålig täckning
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true             // vänta in nät istället för att faila direkt
        config.networkServiceType = .responsiveData    // normal bakgrundsdata
        let session = URLSession(configuration: config)

        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                // Explicit log for network-related failures
                if let urlError = error as? URLError {
                    LogManager.shared.log(
                        category: .nightscout,
                        message: "🌐 Nightscout executeRequest network error (\(urlError.code)): \(urlError.localizedDescription)",
                        limitIdentifier: "Nightscout executeRequest network error"
                    )
                } else {
                    LogManager.shared.log(
                        category: .nightscout,
                        message: "🌐 Nightscout executeRequest error: \(error.localizedDescription)",
                        limitIdentifier: "Nightscout executeRequest generic error"
                    )
                }

                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }

            guard let data = data else {
                LogManager.shared.log(
                    category: .nightscout,
                    message: "🌐 Nightscout executeRequest failed: no data received (possible network issue)",
                    limitIdentifier: "Nightscout executeRequest no data"
                )
                DispatchQueue.main.async {
                    completion(.failure(NightscoutError.networkError))
                }
                return
            }

            let decoder = JSONDecoder()
            do {
                let decodedObject = try decoder.decode(T.self, from: data)
                DispatchQueue.main.async {
                    completion(.success(decodedObject))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
        task.resume()
    }
    
/* SPARAR GAMMAL KOD NEDANFÖR UNDER TEST AV NY KOD
    static func executeRequest<T: Decodable>(eventType: EventType, parameters: [String: String], completion: @escaping (Result<T, Error>) -> Void) {
        let baseURL = ObservableUserDefaults.shared.url.value
        let token = UserDefaultsRepository.token.value

        guard let url = NightscoutUtils.constructURL(baseURL: baseURL, token: token, endpoint: eventType.endpoint, parameters: parameters) else {
            completion(.failure(NSError(domain: "NightscoutUtils", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to construct URL"])))
            return
        }

        var request = URLRequest(url: url)
        request.cachePolicy = URLRequest.CachePolicy.reloadIgnoringLocalCacheData

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                completion(.failure(error!))
                return
            }

            let decoder = JSONDecoder()
            do {
                let decodedObject = try decoder.decode(T.self, from: data)
                DispatchQueue.main.async {
                    completion(.success(decodedObject))
                }
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }
*/

    static func executeDynamicRequest(eventType: EventType, parameters: [String: String], completion: @escaping (Result<Any, Error>) -> Void) {
        let baseURL = ObservableUserDefaults.shared.url.value
        let token = UserDefaultsRepository.token.value

        guard let url = NightscoutUtils.constructURL(baseURL: baseURL,
                                                     token: token,
                                                     endpoint: eventType.endpoint,
                                                     parameters: parameters) else {
            DispatchQueue.main.async {
                completion(.failure(NightscoutError.invalidURL))
            }
            return
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.networkServiceType = .responsiveData
        let session = URLSession(configuration: config)

        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                // Explicit log for network-related failures
                if let urlError = error as? URLError {
                    LogManager.shared.log(
                        category: .nightscout,
                        message: "🌐 Nightscout executeDynamicRequest network error (\(urlError.code)): \(urlError.localizedDescription)",
                        limitIdentifier: "Nightscout executeDynamicRequest network error"
                    )
                } else {
                    LogManager.shared.log(
                        category: .nightscout,
                        message: "🌐 Nightscout executeDynamicRequest error: \(error.localizedDescription)",
                        limitIdentifier: "Nightscout executeDynamicRequest generic error"
                    )
                }

                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }

            guard let data = data else {
                LogManager.shared.log(
                    category: .nightscout,
                    message: "🌐 Nightscout executeDynamicRequest failed: no data received (possible network issue)",
                    limitIdentifier: "Nightscout executeDynamicRequest no data"
                )
                DispatchQueue.main.async {
                    completion(.failure(NightscoutError.networkError))
                }
                return
            }

            do {
                let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
                DispatchQueue.main.async {
                    completion(.success(jsonObject))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
        task.resume()
    }

    static func createURLRequest(url: String, token: String?, path: String) -> URLRequest? {
        var requestURLString = "\(url)\(path)"

        if let token = token {
            let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token
            requestURLString += "?token=\(encodedToken)"
        }

        guard let requestURL = URL(string: requestURLString) else {
            return nil
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        return request
    }

    static func constructURL(baseURL: String, token: String?, endpoint: String, parameters: [String: String]) -> URL? {
        var components = URLComponents(string: baseURL)
        components?.path = endpoint

        var queryItems = [URLQueryItem]()

        if let token = token, !token.isEmpty {
            queryItems.append(URLQueryItem(name: "token", value: token))
        }

        for (key, value) in parameters {
            queryItems.append(URLQueryItem(name: key, value: value))
        }

        components?.queryItems = queryItems

        return components?.url
    }

    static func verifyURLAndToken(completion: @escaping (NightscoutError?, String?, Bool) -> Void) {
        let urlUser = ObservableUserDefaults.shared.url.value
        let token = UserDefaultsRepository.token.value

        if urlUser.isEmpty {
            completion(.emptyAddress, nil, false)
            return
        }

        guard let _ = URL(string: urlUser), urlUser.hasPrefix("http://") || urlUser.hasPrefix("https://") else {
            completion(.invalidURL, nil, false)
            return
        }

        guard let request = createURLRequest(url: urlUser, token: token, path: "/api/v1/status.json") else {
            completion(.invalidURL, nil, false)
            return
        }

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            var nsWriteAuth = false

            if let httpResponse = response as? HTTPURLResponse {
                switch httpResponse.statusCode {
                case 200:
                    if let data = data {
                        do {
                            if let jsonResponse = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                               let authorized = jsonResponse["authorized"] as? [String: Any],
                               let token = authorized["token"] as? String,
                               let permissionGroups = authorized["permissionGroups"] as? [[String]] {

                                if permissionGroups.contains(where: { $0.contains("*") }) {
                                    nsWriteAuth = true
                                } else if permissionGroups.contains(where: { $0.contains("api:treatments:create") }) {
                                    nsWriteAuth = true
                                }
                                completion(nil, token, nsWriteAuth)
                            } else {
                                completion(nil, nil, false)
                            }
                        } catch {
                            completion(nil, nil, false)
                        }
                    } else {
                        completion(nil, nil, false)
                    }
                case 401:
                    if token.isEmpty {
                        completion(.tokenRequired, nil, false)
                    } else {
                        completion(.invalidToken, nil, false)
                    }
                default:
                    completion(.unknown, nil, false)
                }
            } else {
                if let _ = error {
                    completion(.siteNotFound, nil, false)
                } else {
                    completion(.networkError, nil, false)
                }
            }
        }
        task.resume()
    }

    static func parseDate(_ rawString: String) -> Date? {
        var mutableDate = rawString

        if mutableDate.hasSuffix("Z") {
            mutableDate = String(mutableDate.dropLast())
        }
        else if let offsetRange = mutableDate.range(of: "[\\+\\-]\\d{2}:\\d{2}$",
                                                    options: .regularExpression) {
            mutableDate.removeSubrange(offsetRange)
        }

        mutableDate = mutableDate.replacingOccurrences(
            of: "\\.\\d+",
            with: "",
            options: .regularExpression
        )

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        dateFormatter.locale = Locale(identifier: "en_US")
        dateFormatter.timeZone = TimeZone(abbreviation: "UTC")

        let result = dateFormatter.date(from: mutableDate)
        if result == nil {
            LogManager.shared.log(category: .nightscout, message: "Unable to parse string: '\(mutableDate)'", isDebug: true)
        }
        return result
    }

    static func retrieveJWTToken() async throws -> String {
        let urlUser = ObservableUserDefaults.shared.url.value
        let token = UserDefaultsRepository.token.value

        if urlUser.isEmpty {
            throw NightscoutError.emptyAddress
        }

        guard let request = createURLRequest(url: urlUser, token: token, path: "/api/v1/status.json"),
              urlUser.hasPrefix("http://") || urlUser.hasPrefix("https://") else {
            throw NightscoutError.invalidURL
        }

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.waitsForConnectivity = true
        sessionConfig.networkServiceType = .responsiveData
        let session = URLSession(configuration: sessionConfig)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NightscoutError.networkError
        }

        switch httpResponse.statusCode {
        case 200:
            if let jsonResponse = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let authorized = jsonResponse["authorized"] as? [String: Any],
               let jwtToken = authorized["token"] as? String {
                return jwtToken
            } else {
                throw NightscoutError.invalidToken
            }
        case 401:
            throw token.isEmpty ? NightscoutError.tokenRequired : NightscoutError.invalidToken
        default:
            throw NightscoutError.unknown
        }
    }

    static func executePostRequest<T: Decodable>(eventType: EventType, body: [String: Any]) async throws -> T {
        let jwtToken = try await retrieveJWTToken()
        let baseURL = ObservableUserDefaults.shared.url.value

        guard let url = URL(string: "\(baseURL)\(eventType.endpoint)") else {
            throw NightscoutError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(jwtToken)", forHTTPHeaderField: "Authorization")

        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.waitsForConnectivity = true
        sessionConfig.networkServiceType = .responsiveData
        let session = URLSession(configuration: sessionConfig)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NightscoutError.networkError
        }

        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }
    
    // New DELETE function to remove a treatment by its _id.
    struct DeleteResponse: Decodable {
        let n: Int
        let ok: Int
        let optime: DeleteOptime?
        let electionId: String?
        let operationTime: String?
    }

    struct DeleteOptime: Decodable {
        let ts: String
        let t: Int
    }

    // Generic POST helper that optionally returns the created document (if Nightscout responds with JSON).
    static func executePostRequestRaw(eventType: EventType, body: [String: Any]) async throws -> [String: Any]? {
        let jwtToken = try await retrieveJWTToken()
        let baseURL = ObservableUserDefaults.shared.url.value

        guard let url = URL(string: "\(baseURL)\(eventType.endpoint)") else {
            throw NightscoutError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(jwtToken)", forHTTPHeaderField: "Authorization")

        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.waitsForConnectivity = true
        sessionConfig.networkServiceType = .responsiveData
        let session = URLSession(configuration: sessionConfig)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NightscoutError.networkError
        }

        // Om Nightscout returnerar JSON för det skapade treatmentet, försök parsa det.
        guard !data.isEmpty else { return nil }

        do {
            let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
            if let array = jsonObject as? [[String: Any]], let first = array.first {
                return first
            } else if let dict = jsonObject as? [String: Any] {
                return dict
            } else {
                return nil
            }
        } catch {
            LogManager.shared.log(category: .nightscout, message: "⚠️ POST parse error: \(error)", isDebug: true)
            return nil
        }
    }

    /// Fetch a single treatment document by its Nightscout _id.
    static func fetchTreatmentById(_ treatmentId: String, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        let parameters: [String: String] = [
            "find[_id]": treatmentId
        ]

        LogManager.shared.log(category: .nightscout,
                              message: "🔹 Fetch treatment by id (dynamic) for _id: \(treatmentId)",
                              isDebug: true)

        executeDynamicRequest(eventType: .treatments, parameters: parameters) { result in
            switch result {
            case .failure(let error):
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            case .success(let payload):
                // We expect either an array of dictionaries or a single dictionary.
                if let array = payload as? [[String: Any]], let first = array.first {
                    DispatchQueue.main.async {
                        completion(.success(first))
                    }
                } else if let dict = payload as? [String: Any] {
                    DispatchQueue.main.async {
                        completion(.success(dict))
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(.failure(NightscoutError.unknown))
                    }
                }
            }
        }
    }
    
    // MARK: - Pending entry retry support

    private static let pendingUploadKey = "PendingUploadTreatments"

    static func addPendingUploadDocument(_ doc: [String: Any]) {
        var current = loadPendingUploadDocuments()
        current.append(doc)
        savePendingUploadDocuments(current)
    }

    static func loadPendingUploadDocuments() -> [[String: Any]] {
        guard let data = UserDefaults.standard.data(forKey: pendingUploadKey) else {
            return []
        }
        do {
            let any = try JSONSerialization.jsonObject(with: data, options: [])
            return any as? [[String: Any]] ?? []
        } catch {
            LogManager.shared.log(category: .nightscout, message: "⚠️ Failed to load pending treatment: \(error)", isDebug: true)
            return []
        }
    }

    private static func savePendingUploadDocuments(_ docs: [[String: Any]]) {
        do {
            let data = try JSONSerialization.data(withJSONObject: docs, options: [])
            UserDefaults.standard.set(data, forKey: pendingUploadKey)
        } catch {
            LogManager.shared.log(category: .nightscout, message: "⚠️ Failed to save pending treatment: \(error)", isDebug: true)
        }
    }

    static func clearPendingUploadDocuments() {
        UserDefaults.standard.removeObject(forKey: pendingUploadKey)
    }

    /// Retry any pending treatment documents that previously failed to upload.
    /// Call this e.g. from viewDidAppear in TreatmentsTableView.
    static func retryPendingUploads() async {
        let docs = loadPendingUploadDocuments()
        guard !docs.isEmpty else { return }

        var remaining: [[String: Any]] = []

        for doc in docs {
            do {
                _ = try await executePostRequestRaw(eventType: .treatments, body: doc)
            } catch {
                remaining.append(doc)
                LogManager.shared.log(category: .nightscout, message: "⚠️ Retry upload failed: \(error)", isDebug: true)
            }
        }

        if remaining.isEmpty {
            clearPendingUploadDocuments()
        } else {
            savePendingUploadDocuments(remaining)
        }
    }

    static func executeDeleteRequest(treatmentId: String, completion: @escaping (Result<Any, Error>) -> Void) {
        let baseURL = ObservableUserDefaults.shared.url.value
        let token = UserDefaultsRepository.token.value

        // Updated URL to include the API path
        guard let url = URL(string: "\(baseURL)/api/v1/treatments/\(treatmentId)") else {
            completion(.failure(NSError(domain: "NightscoutUtils", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to construct URL for deletion"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        
        // Add token if needed
        if !token.isEmpty {
            let tokenQuery = "token=\(token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token)"
            if var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                urlComponents.query = tokenQuery
                if let newURL = urlComponents.url {
                    request.url = newURL
                }
            }
        }
        
        LogManager.shared.log(category: .nightscout, message: "DELETE Request URL: \(request.url?.absoluteString ?? "nil")", isDebug: true)
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                DispatchQueue.main.async {
                    completion(.failure(error!))
                }
                return
            }
            
            // Print raw response for debugging.
            if let responseString = String(data: data, encoding: .utf8) {
                LogManager.shared.log(category: .nightscout, message: "DELETE Response: \(responseString)", isDebug: true)
            } else {
                LogManager.shared.log(category: .nightscout, message: "DELETE Response: (Unable to convert data to string)", isDebug: true)
            }
            
            // Attempt to decode the response JSON.
            do {
                let decoder = JSONDecoder()
                let deleteResponse = try decoder.decode(DeleteResponse.self, from: data)
                DispatchQueue.main.async {
                    completion(.success(deleteResponse))
                }
            } catch {
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    DispatchQueue.main.async {
                        completion(.success("Success"))
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(.failure(error))
                    }
                }
            }
        }
        task.resume()
    }
    
    static func constructURLManual(baseURL: String, token: String?, endpoint: String, parameters: [String: String]) -> URL? {
        var urlString = "\(baseURL)\(endpoint)?"
        if let token = token, !token.isEmpty {
            urlString += "token=\(token)&"
        }
        for (key, value) in parameters {
            urlString += "\(key)=\(value)&"
        }
        if urlString.hasSuffix("&") {
            urlString.removeLast()
        }
        return URL(string: urlString)
    }
    
    static func fetchDeviceStatusReasonBeforeTimestamp(timestamp: Date, completion: @escaping (Result<String, Error>) -> Void) {
        let baseURL = ObservableUserDefaults.shared.url.value  // e.g., "https://ivarsnightscout.herokuapp.com"
        let token = UserDefaultsRepository.token.value         // e.g., "loopfollow-bf1773e37f692289"
        
        // Use ISO8601DateFormatter to produce a string like "2025-03-14T12:32:19Z"
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        let fullTimestamp = isoFormatter.string(from: timestamp) // e.g., "2025-03-14T12:32:19Z"
        
        // Build the find filter using the "created_at" field
        // This produces a parameter: find[created_at][$lte]=2025-03-14T12:32:19Z
        let parameters: [String: String] = [
            "find[created_at][$lte]": fullTimestamp,
            "count": "1"
        ]
        
        // Use the endpoint with a trailing slash (as your working URL shows)
        let endpoint = "/api/v1/devicestatus/"
        
        guard let url = constructURLManual(baseURL: baseURL, token: token, endpoint: endpoint, parameters: parameters) else {
            completion(.failure(NightscoutError.invalidURL))
            return
        }
        
        LogManager.shared.log(category: .nightscout, message: "🔹 Final URL: \(url.absoluteString)", isDebug: true)
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        
        // Set headers to mimic a browser request.
        request.setValue("application/json, text/javascript, */*; q=0.01", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.3.1 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let httpResponse = response as? HTTPURLResponse {
                LogManager.shared.log(category: .nightscout, message: "HTTP Status Code: \(httpResponse.statusCode)", isDebug: true)
            }
            
            guard let data = data, error == nil else {
                DispatchQueue.main.async {
                    completion(.failure(error ?? NightscoutError.networkError))
                }
                return
            }
            
            // Uncomment the following for full raw-response logging if needed:
            // if let jsonString = String(data: data, encoding: .utf8) {
            //     print("📦 Raw response: \(jsonString)")
            // }
            
            do {
                guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                      let firstStatus = jsonArray.first,
                      let openaps = firstStatus["openaps"] as? [String: Any],
                      let suggested = openaps["suggested"] as? [String: Any],
                      let reason = suggested["reason"] as? String,
                      let iobValue = suggested["IOB"] as? Double,
                      let bgValueRaw = suggested["bg"] else {
                    throw NightscoutError.unknown
                }
                
                // Convert bgValue to Double if needed
                let bgValue: Double
                if let bgDouble = bgValueRaw as? Double {
                    bgValue = bgDouble
                } else if let bgInt = bgValueRaw as? Int {
                    bgValue = Double(bgInt)
                } else {
                    bgValue = 0.0
                }
                
                // Convert bg to mmol by multiplying with 0.0555
                let bgMmol = bgValue * 0.0555
                let bgString = String(format: "%.1f", bgMmol)
                let iobString = String(format: "%.2f", iobValue)
                
                // Extract and format deliverAt. Expected JSON format: "2025-03-17T02:12:10.963Z"
                var deliverAtString = ""
                if let deliverAtRaw = suggested["deliverAt"] as? String {
                    LogManager.shared.log(category: .nightscout, message: "deliverAtRaw: \(deliverAtRaw)", isDebug: true)
                    // Create a local ISO8601DateFormatter to parse the deliverAt string.
                    let localISOFormatter = ISO8601DateFormatter()
                    localISOFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    if let deliverAtDate = localISOFormatter.date(from: deliverAtRaw) {
                        LogManager.shared.log(category: .nightscout, message: "Parsed deliverAtDate: \(deliverAtDate)", isDebug: true)
                        // Format deliverAt as HH:mm:ss
                        let timeFormatter = DateFormatter()
                        timeFormatter.dateFormat = "HH:mm:ss"
                        timeFormatter.timeZone = TimeZone.current  // Use local time zone
                        deliverAtString = timeFormatter.string(from: deliverAtDate)
                        LogManager.shared.log(category: .nightscout, message: "Formatted deliverAtString: \(deliverAtString)", isDebug: true)
                    } else {
                        LogManager.shared.log(category: .nightscout, message: "⚠️ Could not parse deliverAtRaw", isDebug: true)
                    }
                } else {
                    LogManager.shared.log(category: .nightscout, message: "⚠️ deliverAt not found in JSON", isDebug: true)
                }
                
                // Prepend status time, BG and IOB to the reason string.
                // For example: "Status kl: 02:12:10, BG: 4.5, IOB: 1.23, <original reason>"
                var finalPrefix = ""
                if !deliverAtString.isEmpty {
                    finalPrefix = "💡 FÖRSLAG KL: \(deliverAtString), "
                }
                finalPrefix += "BG: \(bgString), IOB: \(iobString), "
                
                let finalReason = finalPrefix + reason
                
                DispatchQueue.main.async {
                    completion(.success(finalReason))
                }
            } catch {
                LogManager.shared.log(category: .nightscout, message: "⚠️ JSON Parsing Error: \(error)", isDebug: true)
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
        task.resume()
    }
    
    // MARK: - Stats: Profile basal history support
        /// Minimal profilmodell för statistikmotor – vi bryr oss bara om created_at + basalprofil.
    struct StatsProfileDocument: Decodable {
        let created_at: String?
        let store: [String: StatsProfileStore]?
        let defaultProfile: String?
    }

        struct StatsProfileStore: Decodable {
            let basal: [MainViewController.basalProfileStruct]
        }

        /// Hämta alla profildokument nyare än `daysBack` dagar (max 1000 st).
        static func fetchBasalProfilesSince(
            daysBack: Int,
            completion: @escaping (Result<[StatsProfileDocument], Error>) -> Void
        ) {
            let baseURL = ObservableUserDefaults.shared.url.value
            let token = UserDefaultsRepository.token.value

            // Från och med datum: now - daysBack
            let sinceDate = Calendar.current.date(byAdding: .day, value: -daysBack, to: Date()) ?? Date()
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let sinceString = isoFormatter.string(from: sinceDate)

            let parameters: [String: String] = [
                "count": "1000",
                "find[created_at][$gte]": sinceString
            ]

            guard let url = NightscoutUtils.constructURL(
                baseURL: baseURL,
                token: token,
                endpoint: "/api/v1/profile.json",
                parameters: parameters
            ) else {
                DispatchQueue.main.async {
                    completion(.failure(NightscoutError.invalidURL))
                }
                return
            }

            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData

            let config = URLSessionConfiguration.default
            config.waitsForConnectivity = true
            config.networkServiceType = .responsiveData
            let session = URLSession(configuration: config)

            let task = session.dataTask(with: request) { data, response, error in
                if let error = error {
                    DispatchQueue.main.async {
                        completion(.failure(error))
                    }
                    return
                }

                guard let data = data else {
                    DispatchQueue.main.async {
                        completion(.failure(NightscoutError.networkError))
                    }
                    return
                }

                do {
                    let decoder = JSONDecoder()
                    let docs = try decoder.decode([StatsProfileDocument].self, from: data)
                    DispatchQueue.main.async {
                        completion(.success(docs))
                    }
                } catch {
                    DispatchQueue.main.async {
                        completion(.failure(error))
                    }
                }
            }

            task.resume()
        }

}
