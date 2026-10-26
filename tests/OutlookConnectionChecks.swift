import Foundation

final class MockTransport: URLProtocol {
    static var status = 200
    static var response = Data()
    static var lastRequest: URLRequest?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lastRequest = request
        let reply = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: reply, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.response)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct OutlookConnectionChecks {
    static func main() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockTransport.self]
        let session = URLSession(configuration: config)
        let invalid = OutlookClient(clientID: "not-a-client-id", session: session)
        do { _ = try await invalid.beginLogin(); fatalError("Invalid Client ID accepted") }
        catch let failure as OutlookFailure { assert(failure.message.contains("Client ID")) }
        let client = OutlookClient(clientID: "00000000-0000-0000-0000-000000000001", session: session)
        MockTransport.response = Data(#"{"device_code":"fixture-only","user_code":"TEST-CODE","verification_uri":"https://microsoft.com/devicelogin","expires_in":900,"interval":5}"#.utf8)
        let grant = try await client.beginLogin()
        assert(grant.user_code == "TEST-CODE")
        assert(MockTransport.lastRequest?.httpMethod == "POST")
        assert(MockTransport.lastRequest?.url?.host == "login.microsoftonline.com")
        MockTransport.status = 400
        MockTransport.response = Data(#"{"error":"unauthorized_client","error_description":"fixture: do not show raw responses"}"#.utf8)
        do { _ = try await client.beginLogin(); fatalError("Microsoft error ignored") }
        catch let failure as OutlookFailure {
            assert(failure.message.contains("unauthorized_client"))
            assert(!failure.message.contains("fixture"))
        }
        let items = try JSONDecoder().decode([MailItem].self, from: Data(#"[{"id":"m1","subject":"[AGENT] test","from":{"emailAddress":{"address":"me@outlook.com"}},"toRecipients":[{"emailAddress":{"address":"me@outlook.com"}}],"body":{"content":"test body"}}]"#.utf8))
        assert(items[0].body?.content == "test body")
        session.invalidateAndCancel()
        print("Outlook request/decoding/error checks passed (mock transport; no real login)")
    }
}
