import SwiftUI

// MARK: - 铃声选择器界面
struct SoundPickerView: View {
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var soundManager = SoundManager.shared

    @Binding var selectedSoundName: String

    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.1).ignoresSafeArea()

                List {
                    ForEach(AlarmSound.all) { sound in
                        Button(action: {
                            // 选中这个铃声
                            selectedSoundName = sound.id
                            // 立刻试听
                            soundManager.preview(sound: sound)
                        }) {
                            HStack {
                                // 图标
                                Image(systemName: sound.icon)
                                    .font(.system(size: 20))
                                    .foregroundColor(selectedSoundName == sound.id ? .purple : .gray)
                                    .frame(width: 30)

                                // 铃声名
                                Text(sound.localizedDisplayName)
                                    .foregroundColor(.white)
                                    .font(.system(size: 17))

                                Spacer()

                                // 播放中的动画指示器
                                if soundManager.currentlyPlayingId == sound.id {
                                    // 三个跳动的小竖条表示正在播放
                                    HStack(spacing: 3) {
                                        ForEach(0..<3) { i in
                                            Capsule()
                                                .fill(Color.purple)
                                                .frame(width: 3, height: CGFloat([12, 20, 16][i]))
                                        }
                                    }
                                    .animation(.easeInOut(duration: 0.3).repeatForever(autoreverses: true), value: soundManager.currentlyPlayingId)
                                }

                                // 选中的勾
                                if selectedSoundName == sound.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.purple)
                                        .font(.system(size: 16, weight: .bold))
                                        .padding(.leading, 8)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.plain)
            }
            .navigationTitle(L("sound.pickerTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L("common.done")) {
                        soundManager.stop()
                        presentationMode.wrappedValue.dismiss()
                    }
                    .foregroundColor(.purple)
                    .fontWeight(.bold)
                }
            }
            .toolbarBackground(Color(red: 0.05, green: 0.05, blue: 0.1), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .onDisappear {
            soundManager.stop()
        }
    }
}
