//
//  Copyright © 2024 Embrace Mobile, Inc. All rights reserved.
//

import CoreData
import Foundation

#if !EMBRACE_COCOAPOD_BUILDING_SDK
    import EmbraceOTelInternal
    import EmbraceCommonInternal
    import EmbraceCoreDataInternal
#endif

/// Class that handles all the cached upload data generated by the Embrace SDK.
class EmbraceUploadCache {

    private(set) var options: EmbraceUpload.CacheOptions
    let coreData: CoreDataWrapper
    let logger: InternalLogger

    init(options: EmbraceUpload.CacheOptions, logger: InternalLogger) throws {
        self.options = options
        self.logger = logger

        // remove old GRDB sqlite file
        if let url = options.storageMechanism.baseUrl?.appendingPathComponent("db.sqlite") {
            try? FileManager.default.removeItem(at: url)
        }

        // remove active cache if needed
        if options.resetCache,
            let cacheUrl = options.storageMechanism.fileURL {
            try? FileManager.default.removeItem(at: cacheUrl)
        }

        // create core data stack
        let coreDataOptions = CoreDataWrapper.Options(
            storageMechanism: options.storageMechanism,
            enableBackgroundTasks: options.enableBackgroundTasks,
            entities: [UploadDataRecord.entityDescription]
        )
        self.coreData = try CoreDataWrapper(options: coreDataOptions, logger: logger)
    }

    func fetchUploadDataRequest(id: String, type: EmbraceUploadType) -> NSFetchRequest<UploadDataRecord> {
        let request = NSFetchRequest<UploadDataRecord>(entityName: UploadDataRecord.entityName)
        request.predicate = NSPredicate(format: "id == %@ AND type == %i", id, type.rawValue)
        request.fetchLimit = 1

        return request
    }

    /// Fetches the cached upload data for the given identifier.
    /// - Parameters:
    ///   - id: Identifier of the data
    ///   - type: Type of the data
    /// - Returns: The cached `UploadDataRecord`, if any
    public func fetchUploadData(id: String, type: EmbraceUploadType) -> UploadDataRecord? {
        let request = fetchUploadDataRequest(id: id, type: type)
        return coreData.fetch(withRequest: request).first
    }

    /// Fetches all the cached upload data.
    /// - Returns: An array containing all the cached `UploadDataRecords`
    public func fetchAllUploadData() -> [ImmutableUploadDataRecord] {
        let request = NSFetchRequest<UploadDataRecord>(entityName: UploadDataRecord.entityName)

        // fetch
        var result: [ImmutableUploadDataRecord] = []
        coreData.fetchAndPerform(withRequest: request) { records in
            // convert to immutable struct
            result = records.map {
                $0.toImmutable()
            }
        }

        return result
    }

    /// Removes stale data based on size or date, if they're limited in options.
    @discardableResult public func clearStaleDataIfNeeded() -> UInt {
        guard options.cacheDaysLimit > 0 else {
            return 0
        }

        let now = Date().timeIntervalSince1970
        let lastValidTime = now - TimeInterval(options.cacheDaysLimit * 86400)  // (60 * 60 * 24) = 86400 seconds per day
        let recordsToDelete = fetchRecordsToDelete(dateLimit: Date(timeIntervalSince1970: lastValidTime))
        let deleteCount = recordsToDelete.count

        if deleteCount > 0 {
            let span = EmbraceOTel().buildSpan(
                name: "emb-upload-cache-vacuum",
                type: .performance,
                attributes: ["removed": "\(deleteCount)"]
            )
            .markAsPrivate()
            span.setStartTime(time: Date())

            let startedSpan = span.startSpan()
            coreData.deleteRecords(recordsToDelete)
            startedSpan.end()

            return UInt(deleteCount)
        }

        return 0
    }

    /// Saves the given upload data to the cache.
    /// - Parameters:
    ///   - id: Identifier of the data
    ///   - type: Type of the data
    ///   - data: Data to cache
    /// - Returns: Boolean indicating if the operation was successful
    @discardableResult func saveUploadData(id: String, type: EmbraceUploadType, data: Data) -> Bool {

        coreData.performOperation { context in

            // update if it already exists
            let request = fetchUploadDataRequest(id: id, type: type)
            do {
                if let uploadData = try context.fetch(request).first {
                    uploadData.data = data
                    try context.save()
                    return true
                }
            } catch {
                logger.warning("Error upading upload data:\n\(error.localizedDescription)")
            }

            // check limit and delete if necessary
            checkCountLimit(context)

            // insert new
            if let record = UploadDataRecord.create(
                context: context,
                id: id,
                type: type.rawValue,
                data: data,
                attemptCount: 0,
                date: Date()
            ) {

                do {
                    try context.save()
                    return true
                } catch {
                    context.delete(record)
                }
            }
            return false
        }
    }

    // Checks the amount of records stored and deletes the oldest ones if the total amount
    // surpasses the limit.
    func checkCountLimit(_ context: NSManagedObjectContext) {
        guard options.cacheLimit > 0 else {
            return
        }

        do {
            let request = NSFetchRequest<UploadDataRecord>(entityName: UploadDataRecord.entityName)
            let count = try context.count(for: request)

            if count >= self.options.cacheLimit {
                request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
                request.fetchLimit = max(0, count - Int(self.options.cacheLimit) + 10)

                let result = try context.fetch(request)
                for uploadData in result {
                    context.delete(uploadData)
                }

                try context.save()
            }
        } catch {
            logger.error("error checking count limit:\n\(error.localizedDescription)")
        }
    }

    /// Deletes the cached data for the given identifier.
    /// - Parameters:
    ///   - id: Identifier of the data
    ///   - type: Type of the data
    func deleteUploadData(id: String, type: EmbraceUploadType) {
        let request = fetchUploadDataRequest(id: id, type: type)
        coreData.deleteRecords(withRequest: request)
    }

    /// Updates the attempt count of the upload data for the given identifier.
    /// - Parameters:
    ///   - id: Identifier of the data
    ///   - type: Type of the data
    ///   - attemptCount: New attempt count
    /// - Returns: Returns the updated `UploadDataRecord`, if any
    func updateAttemptCount(
        id: String,
        type: EmbraceUploadType,
        attemptCount: Int
    ) {

        let request = fetchUploadDataRequest(id: id, type: type)
        coreData.fetchFirstAndPerform(withRequest: request) { [weak self] record in

            guard let uploadData = record else {
                return
            }

            uploadData.attemptCount = attemptCount

            do {
                try self?.coreData.context.save()
            } catch {
                self?.logger.warning("Error upading attempt count:\n\(error.localizedDescription)")
            }
        }
    }

    /// Fetches all records that should be deleted based on them being older than the passed date
    func fetchRecordsToDelete(dateLimit: Date) -> [UploadDataRecord] {
        let request = NSFetchRequest<UploadDataRecord>(entityName: UploadDataRecord.entityName)
        request.predicate = NSPredicate(format: "date < %@", dateLimit as NSDate)

        return coreData.fetch(withRequest: request)
    }
}
