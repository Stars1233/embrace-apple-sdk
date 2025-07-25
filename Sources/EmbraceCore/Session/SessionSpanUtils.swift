//
//  Copyright © 2024 Embrace Mobile, Inc. All rights reserved.
//

import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk

#if !EMBRACE_COCOAPOD_BUILDING_SDK
    import EmbraceCommonInternal
    import EmbraceStorageInternal
    import EmbraceOTelInternal
    import EmbraceSemantics
#endif

struct SessionSpanUtils {

    static func span(id: SessionIdentifier, startTime: Date, state: SessionState, coldStart: Bool) -> Span {
        EmbraceOTel().buildSpan(name: SpanSemantics.Session.name, type: .session)
            .setStartTime(time: startTime)
            .setAttribute(key: SpanSemantics.Session.keyId, value: id.toString)
            .setAttribute(key: SpanSemantics.Session.keyState, value: state.rawValue)
            .setAttribute(key: SpanSemantics.Session.keyColdStart, value: coldStart)
            .startSpan()
    }

    static func setState(span: Span?, state: SessionState) {
        span?.setAttribute(key: SpanSemantics.Session.keyState, value: state.rawValue)
    }

    static func setHeartbeat(span: Span?, heartbeat: Date) {
        span?.setAttribute(key: SpanSemantics.Session.keyHeartbeat, value: heartbeat.nanosecondsSince1970Truncated)
    }

    static func setTerminated(span: Span?, terminated: Bool) {
        span?.setAttribute(key: SpanSemantics.Session.keyTerminated, value: terminated)
    }

    static func payload(
        from session: EmbraceSession,
        spanData: SpanData? = nil,
        properties: [EmbraceMetadata] = [],
        sessionNumber: Int
    ) -> SpanPayload {
        return SpanPayload(from: session, spanData: spanData, properties: properties, sessionNumber: sessionNumber)
    }
}

extension SpanPayload {
    fileprivate init(
        from session: EmbraceSession,
        spanData: SpanData? = nil,
        properties: [EmbraceMetadata],
        sessionNumber: Int
    ) {
        self.traceId = session.traceId
        self.spanId = session.spanId
        self.parentSpanId = nil
        self.name = SpanSemantics.Session.name
        self.status = session.crashReportId != nil ? Status.sessionCrashedError().name : Status.ok.name
        self.startTime = session.startTime.nanosecondsSince1970Truncated
        self.endTime =
            session.endTime?.nanosecondsSince1970Truncated ?? session.lastHeartbeatTime.nanosecondsSince1970Truncated

        var attributeArray: [Attribute] = [
            Attribute(
                key: SpanSemantics.keyEmbraceType,
                value: SpanType.session.rawValue
            ),
            Attribute(
                key: SpanSemantics.Session.keyId,
                value: session.idRaw
            ),
            Attribute(
                key: SpanSemantics.Session.keyState,
                value: session.state
            ),
            Attribute(
                key: SpanSemantics.Session.keyColdStart,
                value: String(session.coldStart)
            ),
            Attribute(
                key: SpanSemantics.Session.keyTerminated,
                value: String(session.appTerminated)
            ),
            Attribute(
                key: SpanSemantics.Session.keyCleanExit,
                value: String(session.cleanExit)
            ),
            Attribute(
                key: SpanSemantics.Session.keyHeartbeat,
                value: String(session.lastHeartbeatTime.nanosecondsSince1970Truncated)
            ),
            Attribute(
                key: SpanSemantics.Session.keySessionNumber,
                value: String(sessionNumber)
            )
        ]

        if let crashId = session.crashReportId {
            attributeArray.append(
                Attribute(
                    key: SpanSemantics.Session.keyCrashId,
                    value: crashId
                ))
        }

        attributeArray.append(
            contentsOf: properties.compactMap { record in
                guard !record.key.starts(with: "emb.user") else {
                    return nil
                }
                return Attribute(
                    key: String(format: "emb.properties.%@", record.key),
                    value: record.value.description
                )
            }
        )

        self.attributes = attributeArray

        if let spanData = spanData {
            self.events = spanData.events.map { SpanEventPayload(from: $0) }
            self.links = spanData.links.map { SpanLinkPayload(from: $0) }
        } else {
            self.events = []
            self.links = []
        }
    }
}

extension OpenTelemetryApi.Status {
    static func sessionCrashedError() -> Status {
        return Status.error(description: "Session crashed!")
    }
}
