import SwiftUI

/// Primera apertura: pedir la carpeta de música.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("Bienvenido a Octava")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text("Elige la carpeta donde guardas tu colección de MP3.\nOctava la recorrerá con sus subcarpetas y armará tu biblioteca.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
            }

            Button {
                model.chooseFolder()
            } label: {
                Text("Elegir carpeta de música…")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 6)
            }
            .buttonStyle(AccentButtonStyle())
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface)
    }
}
