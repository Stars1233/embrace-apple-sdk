//
//  Copyright © 2024 Embrace Mobile, Inc. All rights reserved.
//

import Foundation

public extension EmbraceUpload {
    enum StorageMechanism {
        case inMemory
        case onDisk(baseURL: URL, fileName: String)
    }

    class CacheOptions {
        /// Determines where the db is going to be
        let storageMechanism: StorageMechanism

        /// Determines the maximum amount of cached requests that will be cached. Use 0 to disable.
        public let cacheLimit: UInt

        /// Determines the maximum amount of days a request will be cached. Use 0 to disable.
        public let cacheDaysLimit: UInt

        public init?(
            cacheBaseUrl: URL,
            cacheFileName: String = "db.sqlite",
            cacheLimit: UInt = 0,
            cacheDaysLimit: UInt = 7
        ) {
            if !cacheBaseUrl.isFileURL {
                return nil
            }

            self.storageMechanism = .onDisk(baseURL: cacheBaseUrl, fileName: cacheFileName)
            self.cacheLimit = cacheLimit
            self.cacheDaysLimit = cacheDaysLimit
        }

        public init(
            named: String,
            cacheLimit: UInt = 0,
            cacheDaysLimit: UInt = 7
        ) {
            self.storageMechanism = .inMemory
            self.cacheLimit = cacheLimit
            self.cacheDaysLimit = cacheDaysLimit
        }
    }
}

extension EmbraceUpload.CacheOptions {
    /// URL pointing to the folder where the storage will be saved
    public var baseUrl: URL? {
        if case let .onDisk(baseURL, _) = storageMechanism {
            return baseURL
        }
        return nil
    }

    /// URL pointing to the folder where the storage will be saved
    public var fileName: String? {
        if case let .onDisk(_, name) = storageMechanism {
            return name
        }
        return nil
    }

    /// URL to the storage file
    public var fileURL: URL? {
        if case let .onDisk(url, filename) = storageMechanism {
            return url.appendingPathComponent(filename)
        }
        return nil
    }
}
