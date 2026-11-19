import SwiftUI

struct MonthPicker: View {
    @Binding var year: Int
    @Binding var month: Int

    private let monthNames = [
        "Jan", "Feb", "Mär", "Apr", "Mai", "Jun",
        "Jul", "Aug", "Sep", "Okt", "Nov", "Dez",
    ]

    var body: some View {
        HStack {
            Button {
                goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(WimgFont.font(.inter, .bold, 17, relativeTo: .body))
                    .foregroundStyle(WimgTheme.text)
                    .frame(width: 40, height: 40)
                    .background(WimgTheme.cardBg)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
            }

            Spacer()

            Text("\(monthNames[month - 1]) \(String(year))")
                .font(WimgFont.font(.manrope, .bold, 17, relativeTo: .headline))
                .foregroundStyle(WimgTheme.text)

            Spacer()

            Button {
                goForward()
            } label: {
                Image(systemName: "chevron.right")
                    .font(WimgFont.font(.inter, .bold, 17, relativeTo: .body))
                    .foregroundStyle(WimgTheme.text)
                    .frame(width: 40, height: 40)
                    .background(WimgTheme.cardBg)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
            }
        }
        .padding(.horizontal)
    }

    private func goBack() {
        if month == 1 {
            month = 12
            year -= 1
        } else {
            month -= 1
        }
    }

    private func goForward() {
        if month == 12 {
            month = 1
            year += 1
        } else {
            month += 1
        }
    }
}
