# 文法册 iOS

原生 SwiftUI iOS 应用，最低支持 iOS 17。题库从仓库根目录的 `data.js` 转换并内置为 `WenfaCe/Resources/Grammar.json`。

## 打开与首次配置

1. 用 Xcode 打开 `WenfaCe.xcodeproj`。
2. 在 target 的 Signing & Capabilities 中选择开发团队。
3. 确认 iCloud capability 使用容器 `iCloud.com.2o48.jlptgrammartest`，并在 Apple Developer 账户中创建该容器。
4. 选择真机或模拟器运行。CloudKit 和 iCloud Keychain 的跨设备同步需在真机、已登录 iCloud 的条件下验证。

练习记录经 SwiftData 存储并由 CloudKit 同步。Token 不进入 CloudKit；它使用带 `kSecAttrSynchronizable` 的 iCloud Keychain 项目保存。接口地址、模型和附加指令使用 iCloud Key-Value Store 同步。
