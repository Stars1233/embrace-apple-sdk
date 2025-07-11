//
//  Copyright © 2024 Embrace Mobile, Inc. All rights reserved.
//

import Foundation

@objc public enum LastRunState: Int {
    case unavailable, crash, cleanExit
}

@objc public protocol CrashReporter {
    @objc var currentSessionId: String? { get set }

    @objc func install(context: CrashReporterContext, logger: InternalLogger)

    @objc func getLastRunState() -> LastRunState

    @objc func deleteCrashReport(id: Int)
    @objc func fetchUnsentCrashReports(completion: @escaping ([EmbraceCrashReport]) -> Void)

    @objc var onNewReport: ((EmbraceCrashReport) -> Void)? { get set }

    @objc var disableMetricKitReports: Bool { get }
}

/// This protocol that extends the functionality of a `EmbraceCrashReporter` and it allows
/// implementers to add additional information to crash reports and extend them.
///
/// Implementing this protocol is optional and should only be considered in cases where
/// additional customization in error reporting is required.
public protocol ExtendableCrashReporter: CrashReporter {
    func appendCrashInfo(key: String, value: String)
}

@objc public class EmbraceCrashReport: NSObject {
    public private(set) var id: UUID
    public private(set) var payload: String
    public private(set) var provider: String
    public private(set) var internalId: Int?
    public private(set) var sessionId: String?
    public private(set) var timestamp: Date?

    public init(
        payload: String,
        provider: String,
        internalId: Int? = nil,
        sessionId: String? = nil,
        timestamp: Date? = nil
    ) {
        self.id = UUID()
        self.payload = payload
        self.provider = provider
        self.internalId = internalId
        self.sessionId = sessionId
        self.timestamp = timestamp
    }
}
