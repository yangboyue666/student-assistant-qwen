# 学生智能助手 App

本地优先、离线可用、免费无 API 调用成本的端侧 AI 学生助手。

## 核心功能

| 功能 | 说明 |
|------|------|
| AI 对话助手 | 本地智能助手（离线模式），流式输出，支持函数调用解析日程/作业/课程 |
| 日程安排与提醒 | 自然语言输入日程 → AI 解析 → 自动创建 + 本地通知提醒 |
| 作业进度管理 | 添加/筛选/排序作业，截止前 24 小时本地通知 |
| 课程表 | 手动录入课程信息，周视图网格展示，支持上传课程表照片 |
| 表格数据 | 手动录入，支持导出 CSV / 复制为 Markdown |
| 通用图片上传 | 拍照/相册选图，保存到应用目录 |

## 技术栈

- **框架**: Flutter 3.24+ / Dart 3.5+
- **状态管理**: flutter_riverpod
- **本地数据库**: SQLite (sqflite)
- **本地通知**: flutter_local_notifications + timezone
- **后台任务**: workmanager
- **相机/图片**: image_picker
- **端侧 AI**: PatternBasedLlmService（离线模式匹配 + 模板回复 + 函数调用）

## UI 设计

全局采用**液态玻璃（Liquid Glass）**视觉规范：

- `BackdropFilter` + `ImageFilter.blur(20px)` 实现毛玻璃
- 半透明卡片 + 微弱高光边框
- 大圆角设计（24–32）
- 渐变背景 + 流光文字特效
- 呼吸圆点 / 环形进度条 / 波形条动效
- 渐入渐出 + 缩放过渡动画（Curves.easeOutCubic）

## 构建方式

### 环境要求

- Flutter SDK 3.24+
- Android SDK（最低 API 29，target API 35）
- JDK 17+

### 构建命令

```bash
flutter pub get
flutter build apk --release
```

生成的 APK 位于：`build/app/outputs/flutter-apk/app-release.apk`

### 启用真实端侧 LLM（Qwen3-0.6B）

App 内置**独立的「本地 AI 模型管理」页**，无需手动构建：

1. 在聊天页点击顶部的「升级为千问大模型」小芯片，或在主界面点聊天框头部的记忆体图标，进入模型管理页。
2. 点「开始下载」，App 会自动在多个镜像源（hf-mirror / ModelScope / Hugging Face）之间切换，带进度与文件校验。
3. 下载完成后**后台自动加载并热接入**当前对话框：顶部小芯片变为「千问已启用」，直接在原对话框聊天即可，不会弹出任何遮挡框。

下载入口与聊天历史完全分离，未下载或正在下载时都能正常查看对话历史；不下载时继续使用离线 PatternBasedLlmService。

## 项目结构

```
lib/
├── main.dart                    # 应用入口
├── app.dart                     # MaterialApp 配置
├── core/
│   ├── background/              # workmanager 后台任务
│   ├── db/                      # SQLite 数据库
│   ├── llm/                     # LLM 服务 + AI 工具定义
│   ├── notifications/           # 本地通知
│   ├── theme/                   # 液态玻璃主题
│   ├── utils/                   # 自然语言日期解析
│   └── providers.dart           # Riverpod Providers
├── features/
│   ├── welcome/                 # 欢迎界面（打字效果）
│   ├── hub/                     # 主界面（中央 AI + 4 入口）
│   ├── chat/                    # AI 对话
│   ├── schedule/                # 日程安排
│   ├── assignments/             # 作业管理
│   ├── courses/                 # 课程表
│   ├── tables/                  # 表格数据
│   └── images/                  # 图片上传服务
├── shared/widgets/              # 玻璃组件库
└── router/                       # 路由
```

## AIDE 使用说明（备选方案）

如需在 AIDE 中使用本项目，需手动引入以下依赖（AIDE 内置库较少）：

### 必需依赖

```
flutter_riverpod: ^2.5.1
sqflite: ^2.3.3+1
path: ^1.9.0
path_provider: ^2.1.4
shared_preferences: ^2.3.2
flutter_local_notifications: ^17.2.4
timezone: ^0.9.4
workmanager: ^0.5.2
image_picker: ^1.1.2
intl: ^0.19.0
uuid: ^4.5.1
collection: ^1.18.0
logger: ^2.4.0
google_fonts: ^6.2.1
flutter_animate: ^4.5.0
shimmer: ^3.0.0
file_picker: ^8.1.4
```

### AIDE 注意事项

- AIDE 对 Kotlin DSL（`.gradle.kts`）支持有限，建议改用 Groovy DSL（`build.gradle`）
- `flutter_local_notifications`、`workmanager` 等插件需配置对应的 Android 原生权限和注册代码
- `image_picker` 需在 `AndroidManifest.xml` 中声明相机和存储权限
- 确认 `compileSdk = 35`、`minSdk = 29`、`targetSdk = 35`
- JDK 17 编译

## 最低系统要求

- Android 10（API 29）及以上
```
