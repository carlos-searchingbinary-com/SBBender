import os

/// Centralized logging for SBBender, using `os.Logger` with category-based channels.
public enum Log {
    private static let subsystem = "com.sbbender"

    public static let agent = Logger(subsystem: subsystem, category: "agent")
    public static let model = Logger(subsystem: subsystem, category: "model")
    public static let tool = Logger(subsystem: subsystem, category: "tool")
    public static let skill = Logger(subsystem: subsystem, category: "skill")
    public static let swarm = Logger(subsystem: subsystem, category: "swarm")
    public static let workflow = Logger(subsystem: subsystem, category: "workflow")
    public static let storage = Logger(subsystem: subsystem, category: "storage")
    public static let knowledge = Logger(subsystem: subsystem, category: "knowledge")
    public static let learning = Logger(subsystem: subsystem, category: "learning")
    public static let container = Logger(subsystem: subsystem, category: "container")
    public static let openclaw = Logger(subsystem: subsystem, category: "openclaw")
}
