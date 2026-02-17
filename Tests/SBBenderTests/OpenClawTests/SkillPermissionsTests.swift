import Testing
import Foundation
@testable import SBBender

@Suite("SkillPermissions")
struct SkillPermissionsTests {

    @Test("locked permissions deny everything by default")
    func lockedPermissions() {
        let perms = SkillPermissions.locked
        #expect(perms.approvedEnvVars.isEmpty)
        #expect(perms.networkAccess == false)
        #expect(perms.timeoutSeconds == 30)
        #expect(perms.maxOutputBytes == 1_048_576)
    }

    @Test("custom permissions")
    func customPermissions() {
        let perms = SkillPermissions(
            approvedEnvVars: ["API_KEY": "secret123"],
            networkAccess: true,
            timeoutSeconds: 60,
            maxOutputBytes: 2_097_152
        )
        #expect(perms.approvedEnvVars["API_KEY"] == "secret123")
        #expect(perms.networkAccess == true)
        #expect(perms.timeoutSeconds == 60)
        #expect(perms.maxOutputBytes == 2_097_152)
    }

    @Test("permissions are Codable")
    func codable() throws {
        let perms = SkillPermissions(
            approvedEnvVars: ["KEY": "val"],
            networkAccess: true,
            timeoutSeconds: 45,
            maxOutputBytes: 512_000
        )
        let data = try JSONEncoder().encode(perms)
        let decoded = try JSONDecoder().decode(SkillPermissions.self, from: data)
        #expect(decoded == perms)
    }

    @Test("DenyAllPermissionDelegate denies env vars")
    func denyAllEnvVars() async {
        let delegate = DenyAllPermissionDelegate()
        let result = await delegate.approveEnvironmentVariables(
            skill: "test", requested: ["API_KEY", "SECRET"]
        )
        #expect(result.isEmpty)
    }

    @Test("DenyAllPermissionDelegate denies network")
    func denyAllNetwork() async {
        let delegate = DenyAllPermissionDelegate()
        let result = await delegate.approveNetworkAccess(skill: "test")
        #expect(result == false)
    }

    @Test("AllowAllPermissionDelegate approves known env vars")
    func allowAllEnvVars() async {
        let delegate = AllowAllPermissionDelegate(envVars: [
            "API_KEY": "key123",
            "SECRET": "sec456",
        ])
        let result = await delegate.approveEnvironmentVariables(
            skill: "test", requested: ["API_KEY", "UNKNOWN"]
        )
        #expect(result["API_KEY"] == "key123")
        #expect(result["UNKNOWN"] == nil) // not in delegate's env vars
    }

    @Test("AllowAllPermissionDelegate approves network")
    func allowAllNetwork() async {
        let delegate = AllowAllPermissionDelegate()
        let result = await delegate.approveNetworkAccess(skill: "test")
        #expect(result == true)
    }

    @Test("permissions equality")
    func equality() {
        let a = SkillPermissions(approvedEnvVars: ["K": "V"], networkAccess: true)
        let b = SkillPermissions(approvedEnvVars: ["K": "V"], networkAccess: true)
        let c = SkillPermissions(approvedEnvVars: ["K": "V"], networkAccess: false)

        #expect(a == b)
        #expect(a != c)
    }
}
