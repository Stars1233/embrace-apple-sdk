//
//  Copyright © 2023 Embrace Mobile, Inc. All rights reserved.
//

import EmbraceCommonInternal
import EmbraceStorageInternal
import OpenTelemetryApi
import TestSupport
import XCTest

@testable import EmbraceCore

class LogPayloadBuilderTests: XCTestCase {
    func test_build_addsLogIdAttribute() throws {
        let logId = LogIdentifier(value: try XCTUnwrap(UUID(uuidString: "53B55EDD-889A-4876-86BA-6798288B609C")))
        let record = MockLog(
            id: logId,
            processId: .random,
            severity: .info,
            body: "Hello World",
            attributes: .empty()
        )

        let payload = LogPayloadBuilder.build(log: record)

        let attribute = payload.attributes.first(where: { $0.key == "log.record.uid" })
        XCTAssertNotNil(attribute)
        XCTAssertEqual(attribute?.value, logId.toString)
    }

    func test_buildLogRecordWithAttributes_mapsKeyValuesAsAttributeStruct() {
        let originalAttributes: [String: AttributeValue] = [
            "string_attribute": .string("string"),
            "integer_attribute": .int(1),
            "boolean_attribute": .bool(false),
            "double_attribute": .double(5.0)
        ]
        let record = MockLog(
            id: .random,
            processId: .random,
            severity: .info,
            body: .random(),
            attributes: originalAttributes
        )

        let payload = LogPayloadBuilder.build(log: record)

        XCTAssertGreaterThanOrEqual(payload.attributes.count, originalAttributes.count)

        for (key, value) in originalAttributes {
            let attribute = payload.attributes.first(where: { $0.key == key && $0.value == value.description })
            XCTAssertNotNil(attribute)
        }
    }

    func test_manualBuild() throws {
        // given a session in storage
        let storage = try EmbraceStorage.createInMemoryDb()
        storage.addSession(
            id: TestConstants.sessionId,
            processId: TestConstants.processId,
            state: .foreground,
            traceId: TestConstants.traceId,
            spanId: TestConstants.spanId,
            startTime: Date(timeIntervalSince1970: 0),
            endTime: Date(timeIntervalSince1970: 60)
        )

        // given metadata in storage of that session
        storage.addMetadata(
            key: AppResourceKey.appVersion.rawValue,
            value: "1.0.0",
            type: .requiredResource,
            lifespan: .permanent
        )
        storage.addMetadata(
            key: UserResourceKey.name.rawValue,
            value: "test",
            type: .customProperty,
            lifespan: .session,
            lifespanId: TestConstants.sessionId.toString
        )
        storage.addMetadata(
            key: "tag1",
            value: "tag1",
            type: .personaTag,
            lifespan: .permanent
        )
        storage.addMetadata(
            key: "tag2",
            value: "tag2",
            type: .personaTag,
            lifespan: .session,
            lifespanId: TestConstants.sessionId.toString
        )

        // when manually building a log payload
        let timestamp = Date(timeIntervalSince1970: 30)
        let payload = LogPayloadBuilder.build(
            timestamp: timestamp,
            severity: .fatal,
            body: "test",
            attributes: [
                "key1": "value1",
                "key2": "value2"
            ],
            storage: storage,
            sessionId: TestConstants.sessionId
        )

        // then the payload is correct
        XCTAssertEqual(payload.resource.appVersion, "1.0.0")
        XCTAssertEqual(payload.metadata.username, "test")
        XCTAssertEqual(payload.metadata.personas, ["tag1", "tag2"])

        let logs = try XCTUnwrap(payload.data["logs"])
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs[0].body, "test")
        XCTAssertEqual(logs[0].timeUnixNano, String(timestamp.nanosecondsSince1970Truncated))
        XCTAssertEqual(logs[0].severityNumber, LogSeverity.fatal.number)
        XCTAssertEqual(logs[0].severityText, LogSeverity.fatal.text)

        let attribute1 = logs[0].attributes.first { $0.key == "key1" }
        XCTAssertEqual(attribute1!.value, "value1")

        let attribute2 = logs[0].attributes.first { $0.key == "key2" }
        XCTAssertEqual(attribute2!.value, "value2")
    }
}
