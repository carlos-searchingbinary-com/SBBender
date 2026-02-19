import Testing
import Foundation
@testable import SBBenderCore

@Suite("Message Tests")
struct MessageTests {

    @Test("Create text messages with convenience methods")
    func testConvenienceMessages() {
        let system = Message.system("You are helpful")
        #expect(system.role == .system)
        #expect(system.text == "You are helpful")

        let user = Message.user("Hello")
        #expect(user.role == .user)
        #expect(user.text == "Hello")

        let assistant = Message.assistant("Hi there")
        #expect(assistant.role == .assistant)
        #expect(assistant.text == "Hi there")
    }

    @Test("Create tool result messages")
    func testToolMessage() {
        let toolMsg = Message.tool(id: "call-123", result: "42", name: "calculator")
        #expect(toolMsg.role == .tool)
        #expect(toolMsg.text == "42")
        #expect(toolMsg.toolCallID == "call-123")
        #expect(toolMsg.name == "calculator")
    }

    @Test("Multimodal message with images")
    func testMultimodalMessage() {
        let image = ImageContent.data(Data([0xFF, 0xD8]), mimeType: "image/jpeg")
        let msg = Message.user("What is this?", images: [image])

        #expect(msg.content.count == 2)
        #expect(msg.text == "What is this?")
        #expect(msg.images.count == 1)
        #expect(msg.images.first?.mimeType == "image/jpeg")
    }

    @Test("Message ID is unique")
    func testUniqueIDs() {
        let m1 = Message.user("a")
        let m2 = Message.user("b")
        #expect(m1.id != m2.id)
    }

    @Test("Message Codable roundtrip")
    func testCodable() throws {
        let original = Message.user("Hello world")
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(Message.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.role == original.role)
        #expect(decoded.text == original.text)
    }

    @Test("ToolCall decodes arguments")
    func testToolCallDecode() throws {
        struct CalcArgs: Decodable {
            let a: Int
            let b: Int
        }

        let tc = ToolCall(name: "add", arguments: #"{"a": 1, "b": 2}"#)
        let args = try tc.decodeArguments(CalcArgs.self)
        #expect(args.a == 1)
        #expect(args.b == 2)
    }
}

@Suite("Content Tests")
struct ContentTests {
    @Test("Text content value extraction")
    func testTextValue() {
        let text = Content.text("hello")
        #expect(text.textValue == "hello")
        #expect(text.isText)

        let image = Content.image(ImageContent.data(Data()))
        #expect(image.textValue == nil)
        #expect(!image.isText)
    }
}

@Suite("Media Content Tests")
struct MediaContentTests {
    @Test("ImageContent from data")
    func testImageData() {
        let img = ImageContent.data(Data([1, 2, 3]), mimeType: "image/png")
        #expect(img.mimeType == "image/png")
        if case .data(let d) = img.source {
            #expect(d.count == 3)
        } else {
            Issue.record("Expected data source")
        }
    }

    @Test("ImageContent from URL")
    func testImageURL() {
        let img = ImageContent.url(URL(string: "https://example.com/img.png")!)
        if case .url(let u) = img.source {
            #expect(u.absoluteString == "https://example.com/img.png")
        } else {
            Issue.record("Expected URL source")
        }
    }

    @Test("MediaSource resolveData from data")
    func testResolveData() throws {
        let source = MediaSource.data(Data([42]))
        let resolved = try source.resolveData()
        #expect(resolved == Data([42]))
    }
}
