# 课间猫擂台 · Campus Cats Duel

五只校园猫的 2D 对战游戏。奶糖能用双掌把对手震飞，布丁靠变向和掠爪抓收招。美年达、烤鸭博士和橘猪则带着无影脚、磁轨炮和电车上场。每回合 45 秒，三局两胜。

## 开始玩

在本仓库的 **Releases** 页面下载试玩版。

- **Windows** 支持人机和同键盘双人。解压 Windows 版 ZIP，双击 `CampusCatsDuel.exe`，同目录的 `CampusCatsDuel.pck` 是游戏数据。
- **iPhone** 支持横屏触控人机对战。将 Web 版 ZIP 解压到提供 HTTPS 的静态网站后，用 Safari 打开；也可以把 ZIP 保存到 iPhone 的“文件”，解压，再用 Local Vibe Runner 导入包含 `index.html` 的整个文件夹，点 **Preview**。在线试玩可直接用 Safari 横屏打开。左手推摇杆移动、跳跃或格挡，右手点轻击、重击、投技和两档必杀。手机初次进入默认简单，点选角页上方的难度可切回普通。[手机网页版](https://charlie2324388.github.io/CampusCatsDuel/)

## 操作

| 1P 按键 | 动作 |
| --- | --- |
| A / D | 移动 |
| W / 按住 S | 跳跃 / 格挡 |
| J / K / L | 轻击 / 重击 / 近身投 |
| U / I | 消耗一气 / 两气发动必杀 |
| F1 | 打开连招表 |

贴身轻击两次，看到命中火花后按 I，可以把两气大招接进连招。格挡能挡住必杀，近身投能抓住格挡的对手。[完整玩法和 2P 键位](玩法.txt)

## 从源码运行

1. 使用 Godot 4.7.2 标准版导入仓库根目录的 `project.godot`。
2. 首次打开时等美术与音频导入完成，按 **F6** 可试玩打开的主场景，按 **F5** 直接运行游戏。
3. 要导出可分发的版本，在编辑器中安装同版本的官方导出模板，再选择 **Windows Desktop** 或 **iPhone Safari** 预设。使用 Web 预设前，先创建 `build/iphone/` 文件夹。

在仓库根目录可运行战斗规则检查：

```sh
godot --headless --import
godot --headless --fixed-fps 60 --script dev/new_roster_checks.gd
```

## 许可证

项目代码、文档和项目原创美术与音效采用 [MIT 许可证](LICENSE)。项目中的角色插画使用图像生成工具制作。中文界面字体基于 Noto Sans SC 裁剪，采用 [SIL Open Font License 1.1](art/fonts/OFL.txt)。发行包使用 Godot 引擎，并随附引擎与第三方组件的许可声明。[Godot 许可说明](https://godotengine.org/license/)
