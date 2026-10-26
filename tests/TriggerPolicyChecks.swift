import Foundation
@main struct TriggerPolicyChecks {
    static func main() {
        let policy = TriggerPolicy(ownAddress: "me@qq.com", prefix: "[AGENT]")
        assert(policy.accepts(sender: "me@qq.com", recipients: ["me@qq.com"], subject: "[AGENT] check status"))
        assert(!policy.accepts(sender: "other@qq.com", recipients: ["me@qq.com"], subject: "[AGENT] check status"))
        assert(!policy.accepts(sender: "me@qq.com", recipients: ["other@qq.com"], subject: "[AGENT] check status"))
        assert(!policy.accepts(sender: "me@qq.com", recipients: ["me@qq.com"], subject: "Re: [AGENT] check status"))
        assert(!policy.accepts(sender: "me@qq.com", recipients: ["me@qq.com"], subject: "[AGENT] "))
        assert(!policy.accepts(sender: "me@qq.com", recipients: ["me@qq.com"], subject: "[AGENT] check status", autoSubmitted: "auto-replied"))
        assert(!TriggerPolicy(ownAddress: "", prefix: "[AGENT]").accepts(sender: "", recipients: [""], subject: "[AGENT] check status"))
        print("Trigger policy checks passed")
    }
}
