import Foundation

// MARK: - Data Model

/// Parsed representation of a SKILL.md file from an OpenClaw skill package.
public struct SkillManifest: Sendable, Codable, Equatable {
    /// Unique name of the skill (e.g. "web-scraper").
    public let name: String
    /// URL-safe slug derived from name.
    public let slug: String
    /// Human-readable description.
    public let description: String
    /// Semantic version string (e.g. "1.0.0").
    public let version: String
    /// Runtime requirements (binaries, env vars, install commands).
    public let requirements: SkillRequirements
    /// Primary execution environment hint (e.g. "node", "python", "sh").
    public let primaryEnv: String?
    /// Supported operating systems (e.g. ["linux"]).
    public let os: [String]
    /// Markdown body after frontmatter — the skill's instructions/docs.
    public let instructions: String
    /// Relative paths to supporting scripts/configs in the skill directory.
    public let supportingFiles: [String]
    /// Host directory where the skill is stored.
    public let localPath: URL

    public init(
        name: String,
        slug: String,
        description: String,
        version: String,
        requirements: SkillRequirements = SkillRequirements(),
        primaryEnv: String? = nil,
        os: [String] = ["linux"],
        instructions: String = "",
        supportingFiles: [String] = [],
        localPath: URL
    ) {
        self.name = name
        self.slug = slug
        self.description = description
        self.version = version
        self.requirements = requirements
        self.primaryEnv = primaryEnv
        self.os = os
        self.instructions = instructions
        self.supportingFiles = supportingFiles
        self.localPath = localPath
    }
}

/// Runtime requirements declared in SKILL.md frontmatter.
public struct SkillRequirements: Sendable, Codable, Equatable {
    /// Environment variable names the skill needs (e.g. ["OPENAI_API_KEY"]).
    public var env: [String]
    /// Required binaries that must all be present (e.g. ["node", "npx"]).
    public var bins: [String]
    /// Alternative binaries — at least one must be present (e.g. ["curl", "wget"]).
    public var anyBins: [String]
    /// Configuration keys the skill reads.
    public var config: [String]
    /// Install commands to run during setup (e.g. ["npm install"]).
    public var install: [String]

    public init(
        env: [String] = [],
        bins: [String] = [],
        anyBins: [String] = [],
        config: [String] = [],
        install: [String] = []
    ) {
        self.env = env
        self.bins = bins
        self.anyBins = anyBins
        self.config = config
        self.install = install
    }
}

// MARK: - Parser

/// Parses SKILL.md files into ``SkillManifest`` values.
///
/// SKILL.md uses YAML frontmatter (delimited by `---`) followed by a Markdown body.
/// This is a minimal, dependency-free parser covering the subset used by OpenClaw skills:
/// string scalars, arrays (both `[a,b]` inline and `- a` block), and nested objects up to 3 levels.
public struct SkillManifestParser {

    /// Parse a skill directory containing a SKILL.md file.
    public static func parse(directory: URL) throws -> SkillManifest {
        let skillFile = directory.appendingPathComponent("SKILL.md")
        let content: String
        do {
            content = try String(contentsOf: skillFile, encoding: .utf8)
        } catch {
            throw SBBenderError.skillManifestInvalid(
                path: skillFile.path,
                reason: "Cannot read SKILL.md: \(error.localizedDescription)"
            )
        }

        guard let (yaml, body) = extractFrontmatter(from: content) else {
            throw SBBenderError.skillManifestInvalid(
                path: skillFile.path,
                reason: "No YAML frontmatter found (expected --- delimiters)"
            )
        }

        let fields = parseYAMLFrontmatter(yaml)

        guard let name = fields["name"] as? String, !name.isEmpty else {
            throw SBBenderError.skillManifestInvalid(path: skillFile.path, reason: "Missing required field: name")
        }
        guard let description = fields["description"] as? String else {
            throw SBBenderError.skillManifestInvalid(path: skillFile.path, reason: "Missing required field: description")
        }

        let slug = (fields["slug"] as? String) ?? name.slugified
        let version = (fields["version"] as? String) ?? "0.1.0"
        let primaryEnv = fields["primaryEnv"] as? String ?? fields["primary_env"] as? String
        let os = parseStringArray(fields["os"]) ?? ["linux"]

        // Parse requirements from nested "requires" or "requirements" key
        let reqDict = (fields["requires"] as? [String: Any]) ?? (fields["requirements"] as? [String: Any]) ?? [:]
        let requirements = SkillRequirements(
            env: parseStringArray(reqDict["env"]) ?? [],
            bins: parseStringArray(reqDict["bins"]) ?? [],
            anyBins: parseStringArray(reqDict["anyBins"] ?? reqDict["any_bins"]) ?? [],
            config: parseStringArray(reqDict["config"]) ?? [],
            install: parseStringArray(reqDict["install"]) ?? []
        )

        // Discover supporting files in the directory
        let supportingFiles = discoverSupportingFiles(in: directory)

        return SkillManifest(
            name: name,
            slug: slug,
            description: description,
            version: version,
            requirements: requirements,
            primaryEnv: primaryEnv,
            os: os,
            instructions: body.trimmingCharacters(in: .whitespacesAndNewlines),
            supportingFiles: supportingFiles,
            localPath: directory
        )
    }

    /// Extract YAML frontmatter and Markdown body from a SKILL.md string.
    /// Returns `nil` if no valid frontmatter delimiters are found.
    public static func extractFrontmatter(from content: String) -> (yaml: String, body: String)? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("---") else { return nil }

        // Find the closing ---
        let afterOpening = trimmed.index(trimmed.startIndex, offsetBy: 3)
        let rest = trimmed[afterOpening...]
        guard let closingRange = rest.range(of: "\n---") else { return nil }

        let yaml = String(rest[rest.startIndex..<closingRange.lowerBound])
        let bodyStart = rest.index(closingRange.upperBound, offsetBy: 0)
        let body = String(rest[bodyStart...])

        return (yaml: yaml, body: body)
    }

    /// Parse a minimal YAML string into a dictionary.
    /// Supports: string scalars, inline arrays `[a,b]`, block arrays `- a`, and nested objects (indented keys).
    public static func parseYAMLFrontmatter(_ yaml: String) -> [String: Any] {
        var result: [String: Any] = [:]
        let lines = yaml.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines and comments
            if trimmedLine.isEmpty || trimmedLine.hasPrefix("#") {
                i += 1
                continue
            }

            // Parse key: value
            guard let colonIndex = trimmedLine.firstIndex(of: ":") else {
                i += 1
                continue
            }

            let key = String(trimmedLine[trimmedLine.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces)
            let valueStr = String(trimmedLine[trimmedLine.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)

            let currentIndent = indentLevel(of: line)

            if valueStr.isEmpty {
                // Could be a nested object or block array — peek at next lines
                var nextI = i + 1
                if nextI < lines.count {
                    let nextTrimmed = lines[nextI].trimmingCharacters(in: .whitespaces)
                    let nextIndent = indentLevel(of: lines[nextI])

                    if nextTrimmed.hasPrefix("- ") && nextIndent > currentIndent {
                        // Block array
                        var items: [String] = []
                        while nextI < lines.count {
                            let nl = lines[nextI]
                            let nt = nl.trimmingCharacters(in: .whitespaces)
                            let ni = indentLevel(of: nl)
                            if nt.isEmpty { nextI += 1; continue }
                            guard ni > currentIndent, nt.hasPrefix("- ") else { break }
                            items.append(String(nt.dropFirst(2)).trimmingCharacters(in: .whitespaces).unquoted)
                            nextI += 1
                        }
                        result[key] = items
                        i = nextI
                        continue
                    } else if nextIndent > currentIndent {
                        // Nested object
                        var nested: [String: Any] = [:]
                        while nextI < lines.count {
                            let nl = lines[nextI]
                            let nt = nl.trimmingCharacters(in: .whitespaces)
                            let ni = indentLevel(of: nl)
                            if nt.isEmpty { nextI += 1; continue }
                            guard ni > currentIndent else { break }

                            if let nestedColon = nt.firstIndex(of: ":") {
                                let nKey = String(nt[nt.startIndex..<nestedColon]).trimmingCharacters(in: .whitespaces)
                                let nVal = String(nt[nt.index(after: nestedColon)...]).trimmingCharacters(in: .whitespaces)

                                if nVal.isEmpty {
                                    // Could be a block array inside nested object
                                    var subI = nextI + 1
                                    let subIndent = ni
                                    if subI < lines.count {
                                        let subTrimmed = lines[subI].trimmingCharacters(in: .whitespaces)
                                        let subNI = indentLevel(of: lines[subI])
                                        if subTrimmed.hasPrefix("- ") && subNI > subIndent {
                                            var items: [String] = []
                                            while subI < lines.count {
                                                let sl = lines[subI]
                                                let st = sl.trimmingCharacters(in: .whitespaces)
                                                let si = indentLevel(of: sl)
                                                if st.isEmpty { subI += 1; continue }
                                                guard si > subIndent, st.hasPrefix("- ") else { break }
                                                items.append(String(st.dropFirst(2)).trimmingCharacters(in: .whitespaces).unquoted)
                                                subI += 1
                                            }
                                            nested[nKey] = items
                                            nextI = subI
                                            continue
                                        }
                                    }
                                } else {
                                    nested[nKey] = parseScalarOrInlineArray(nVal)
                                }
                            }
                            nextI += 1
                        }
                        result[key] = nested
                        i = nextI
                        continue
                    }
                }
                // Empty value
                result[key] = ""
                i += 1
                continue
            }

            // Inline value (scalar or inline array)
            result[key] = parseScalarOrInlineArray(valueStr)
            i += 1
        }

        return result
    }

    // MARK: - Private Helpers

    private static func indentLevel(of line: String) -> Int {
        var count = 0
        for char in line {
            if char == " " { count += 1 }
            else if char == "\t" { count += 4 }
            else { break }
        }
        return count
    }

    private static func parseScalarOrInlineArray(_ value: String) -> Any {
        let v = value.unquoted
        // Inline array: [a, b, c]
        if v.hasPrefix("[") && v.hasSuffix("]") {
            let inner = String(v.dropFirst().dropLast())
            return inner.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces).unquoted }
                .filter { !$0.isEmpty }
        }
        return v
    }

    private static func parseStringArray(_ value: Any?) -> [String]? {
        guard let value else { return nil }
        if let arr = value as? [String] { return arr }
        if let str = value as? String { return str.isEmpty ? [] : [str] }
        return nil
    }

    private static func discoverSupportingFiles(in directory: URL) -> [String] {
        let fm = FileManager.default
        // Resolve symlinks to handle /tmp -> /private/tmp on macOS
        let resolvedDir = directory.resolvingSymlinksInPath()
        guard let enumerator = fm.enumerator(at: resolvedDir, includingPropertiesForKeys: nil) else {
            return []
        }
        var files: [String] = []
        let extensions = Set(["mjs", "js", "py", "sh", "bash", "json", "toml", "yaml", "yml", "txt", "cfg"])
        let basePath = resolvedDir.path
        while let url = enumerator.nextObject() as? URL {
            let ext = url.pathExtension.lowercased()
            let name = url.lastPathComponent
            if name == "SKILL.md" { continue }
            if extensions.contains(ext) || name == "Dockerfile" || name == "Makefile" {
                // Relative path from skill directory
                let resolved = url.resolvingSymlinksInPath().path
                let relative = resolved.replacingOccurrences(of: basePath + "/", with: "")
                files.append(relative)
            }
        }
        return files.sorted()
    }
}

// MARK: - String Helpers

extension String {
    /// Remove surrounding quotes (single or double).
    var unquoted: String {
        if (hasPrefix("\"") && hasSuffix("\"")) || (hasPrefix("'") && hasSuffix("'")) {
            return String(dropFirst().dropLast())
        }
        return self
    }

    /// Convert a name to a URL-safe slug.
    var slugified: String {
        lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
    }
}
