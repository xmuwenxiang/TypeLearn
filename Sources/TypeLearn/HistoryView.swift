import SwiftUI

/// 翻译历史列表：时间倒序，显示原文与译文，可复制
struct HistoryView: View {
    @ObservedObject private var store = HistoryStore.shared

    var body: some View {
        VStack(spacing: 0) {
            if store.entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("暂无翻译历史")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    Text("在任意输入框输入中文后，翻译记录会出现在这里")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(store.entries) { entry in
                        HistoryRow(entry: entry)
                    }
                }
                .listStyle(.inset)
            }

            Divider()
            HStack {
                Text("\(store.entries.count) 条记录")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("清空历史") {
                    store.clear()
                }
                .disabled(store.entries.isEmpty)
                .padding(10)
            }
        }
        .frame(minWidth: 440, minHeight: 480)
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry
    @State private var copiedIndex: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.source)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(entry.timestamp.formatted(date: .numeric, time: .shortened))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            ForEach(Array(entry.translations.enumerated()), id: \.offset) { index, translation in
                HStack(alignment: .firstTextBaseline) {
                    Text(translation)
                        .font(.system(size: 13))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    Spacer(minLength: 8)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(translation, forType: .string)
                        copiedIndex = index
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            if copiedIndex == index { copiedIndex = nil }
                        }
                    } label: {
                        Image(systemName: copiedIndex == index ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundStyle(copiedIndex == index ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
