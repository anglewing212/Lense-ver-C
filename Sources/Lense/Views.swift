import SwiftUI
private typealias Stored<Value> = SwiftUI.State<Value>

struct SettingsView: View {
    @Stored<String> private var key = Secret.read()
    @Stored<String> private var message = ""
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Text("Lense").font(.largeTitle.bold())
            Text("⌃⌥ 唤出 · 拖框选中 · 原位解答").foregroundStyle(.secondary)
            SecureField("OpenAI 服务密钥",text:$key)
            Text("模型：GPT 6 astra")
            Text("仅圈选截图会发送至 OpenAI；密钥保存在本机 .env 文件。联网搜索可能另行计费。").font(.caption).foregroundStyle(.secondary)
            HStack {
                Link("获取密钥",destination:URL(string:"https://platform.openai.com/api-keys")!)
                Spacer()
                Button("保存") {
                    do {
                        guard !key.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { message = "请填写密钥。"; return }
                        try Secret.save(key.trimmingCharacters(in:.whitespacesAndNewlines))
                        message = "已保存，可以关闭设置并开始圈选。"
                    } catch { message = "保存失败：\(error.localizedDescription)" }
                }.keyboardShortcut(.defaultAction)
            }
            Text(message).font(.caption)
        }.padding(24).frame(width:420,height:310).textFieldStyle(.roundedBorder)
    }
}
