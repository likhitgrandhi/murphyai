import SwiftUI
import AppKit

// MARK: - View model

@Observable
class InlineInputViewModel {
    var text: String = ""
    var selectedText: String? = nil
    var capturedImage: CGImage? = nil
    var isStreaming: Bool = false
}

// MARK: - Custom NSTextField coordinator (intercepts Enter and Esc)

struct InlinePlainTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onCommit: () -> Void
    var onEscape: () -> Void
    var onFirstKey: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.placeholderString = placeholder
        field.font = NSFont(name: "InterVariable", size: 15) ?? .systemFont(ofSize: 15)
        field.textColor = NSColor(Kin.textPrimary)
        field.cell?.wraps = false
        field.cell?.lineBreakMode = .byClipping
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        context.coordinator.parent = self
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: InlinePlainTextField
        var firstKey = true

        init(_ parent: InlinePlainTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            if firstKey {
                firstKey = false
                parent.onFirstKey()
            }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)) {
                parent.onCommit()
                return true
            }
            if selector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onEscape()
                return true
            }
            return false
        }
    }
}

// MARK: - Inline input view

struct InlineInputView: View {
    @Bindable var vm: InlineInputViewModel
    var onSend: () -> Void
    var onCameraPressed: () -> Void
    var onDismiss: () -> Void
    var onFirstKey: () -> Void

    private var canSend: Bool {
        !vm.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !vm.isStreaming
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            attachmentPills

            HStack(spacing: 8) {
                InlinePlainTextField(
                    text: $vm.text,
                    placeholder: "Ask anything…",
                    onCommit: {
                        if canSend { onSend() }
                    },
                    onEscape: onDismiss,
                    onFirstKey: onFirstKey
                )
                .frame(height: 22)

                cameraButton
                sendButton
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .background(Kin.inputBg, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Kin.border, lineWidth: 1)
        )
        .shadowLg()
        .frame(width: 400)
    }

    @ViewBuilder
    private var attachmentPills: some View {
        if vm.selectedText != nil || vm.capturedImage != nil {
            VStack(alignment: .leading, spacing: 6) {
                if let selected = vm.selectedText {
                    selectedTextPill(selected)
                }
                if let img = vm.capturedImage {
                    imagePill(img)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 2)
        }
    }

    private func selectedTextPill(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "scissors")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Kin.textTertiary)
            Text(text.prefix(60) + (text.count > 60 ? "…" : ""))
                .font(Kin.inter(12))
                .foregroundStyle(Kin.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button { vm.selectedText = nil } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Kin.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Kin.surface, in: RoundedRectangle(cornerRadius: 8))
    }

    private func imagePill(_ cgImage: CGImage) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)))
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 48, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            Text("Screenshot attached")
                .font(Kin.inter(12))
                .foregroundStyle(Kin.textSecondary)
            Spacer(minLength: 0)
            Button { vm.capturedImage = nil } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Kin.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Kin.surface, in: RoundedRectangle(cornerRadius: 8))
    }

    private var cameraButton: some View {
        Button(action: onCameraPressed) {
            Image(systemName: "camera")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(vm.capturedImage != nil ? Kin.accent : Kin.textTertiary)
                .frame(width: 28, height: 28)
                .background(Kin.surface, in: Circle())
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.88))
    }

    private var sendButton: some View {
        Button(action: {
            if canSend { onSend() }
        }) {
            Image(systemName: "arrow.up")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(canSend ? .white : Kin.textTertiary)
                .frame(width: 28, height: 28)
                .background(canSend ? Kin.accent : Color.clear, in: Circle())
        }
        .disabled(!canSend)
        .buttonStyle(PressScaleButtonStyle(scale: 0.88))
        .animation(.spring(response: 0.22, dampingFraction: 0.75), value: canSend)
    }
}
