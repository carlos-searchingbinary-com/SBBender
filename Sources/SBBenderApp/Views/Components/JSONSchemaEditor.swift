import SwiftUI

struct JSONSchemaEditor: View {
    @Binding var parameters: [ToolParamConfig]

    private let typeOptions = ["string", "integer", "number", "boolean"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(parameters.indices, id: \.self) { index in
                parameterRow(index: index)
            }

            Button {
                parameters.append(ToolParamConfig(
                    name: "",
                    type: "string",
                    description: "",
                    required: true
                ))
            } label: {
                Label("Add Input", systemImage: "plus.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
    }

    @ViewBuilder
    private func parameterRow(index: Int) -> some View {
        HStack(spacing: 8) {
            TextField("name", text: $parameters[index].name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
                .font(.system(.body, design: .monospaced))

            Picker("", selection: $parameters[index].type) {
                ForEach(typeOptions, id: \.self) { t in
                    Text(t).tag(t)
                }
            }
            .frame(width: 100)

            TextField("description", text: $parameters[index].description)
                .textFieldStyle(.roundedBorder)

            Toggle("Required", isOn: $parameters[index].required)
                .toggleStyle(.checkbox)
                .frame(width: 80)

            Button {
                parameters.remove(at: index)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
    }

    /// Generate a preview JSON Schema string from current parameters.
    static func previewJSON(from parameters: [ToolParamConfig]) -> String {
        var props: [String: [String: String]] = [:]
        for param in parameters where !param.name.isEmpty {
            var entry: [String: String] = ["type": param.type]
            if !param.description.isEmpty {
                entry["description"] = param.description
            }
            props[param.name] = entry
        }

        let required = parameters.filter { $0.required && !$0.name.isEmpty }.map { $0.name }

        let schema: [String: Any] = [
            "type": "object",
            "properties": props,
            "required": required
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: schema, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }
}
