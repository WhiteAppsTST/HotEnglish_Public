import SwiftUI

struct GradeSelectionBtnView: View {
    let grade: LangGrade
    let isSelected: Bool
    let action: (LangGrade) -> Void
    
    var body: some View {
        Button {
            action(grade)
        } label: {
            HStack(alignment: .center, spacing: 16) {
                Text(grade.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text(grade.grade)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(
                        isSelected ? .white : Color(hex: "#CCCCD6"))
            }
            .padding(.vertical, 15)
            .padding(.horizontal)
            .background(
                isSelected ? Color.lsPink : .white.opacity(0.16),
                in: RoundedRectangle(cornerRadius: 16)
            )
        }
        .animation(.linear(duration: 0.15), value: isSelected)
    }
}

#Preview {
    GradeSelectionBtnView(grade: .aOne, isSelected: true, action: {lang in})
}
