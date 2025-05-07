## DanmakuRender Script
- 由Claude生成.优化
- 适用于**Debian/Ubuntu**
- 快捷安装/卸载,启动/停止录制/快速上传
- ~~其实Docker构建更方便~~
- 最近在学习Next.js 和 Go
- 其实有想法写个图形化web端的 更方便！
- ~~但是懒~~
```bash
bash <(wget -qO- https://raw.githubusercontent.com/sillda76/DanmakuRender/refs/heads/v5/dmr.sh)
```
### Menu
```
DanmakuRender v5 管理脚本
最新发布版本: 2025.04.03 (2025-04-03 14:59:37)
最新代码提交: 2025-04-23 00:19:27
项目地址: https://github.com/SmallPeaches/DanmakuRender
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
程序状态：已安装 (目录: /opt/DanmakuRender-5)
配置文件：已找到 (*DMR* in configs)，共1位主播
运行状态：正在运行 (PID: 1672)
上一次安装/更新：2025-04-24 07:03:08
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. 安装 DanmakuRender v5
2. 停止 录制进程
3. 查看 实时日志 (按 'q' 退出)
4. 实时推送日志到 Telegram
5. 手动渲染 视频 (render_only.py)
6. 运行测试 (dryrun.py)
7. 删除 回放/渲染的视频文件
8. biliup-rs 上传工具菜单
9. 字体 安装菜单 (微软雅黑/阿里普惠/Noto Emoji)
10.安装 JavaScript 环境 (Node.js + quickjs)
11.更新 DanmakuRender v5 (保留配置)
12.卸载 DanmakuRender v5
0. 退出 脚本
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
请输入选项喵~ (0-11):
```
### 安装的目录如下
#### DanmakuRender-v5
```
/opt/DanmakuRender-v5
```
#### biliup-rs
```
/opt/DanmakuRender-v5/tools
```

### [biliup-rs项目地址](https://github.com/biliup/biliup-rs)

#### 以下为原项目的 README.md
---

# DanmakuRender-5 —— 一个录制带弹幕直播的小工具（版本5）
结合网络上的代码写的一个能录制带弹幕直播流的小工具，主要用来录制包含弹幕的视频流。     
- 可以录制纯净直播流和弹幕，并且支持在本地预览带弹幕直播流。
- 可以自动渲染弹幕到视频中，并且渲染速度快。
- 支持同时录制多个直播。    
- 支持录播自动上传至B站。     

此版本为全新设计的版本5，包含以下新功能：     
- 支持动态载入配置文件。
- 支持更加复杂的录制、上传、渲染和清理逻辑。
- 支持搬运直播回放或者视频。
- 支持使用webhook与其他录制软件协同（正在开发）。

旧版本可以在分支v1-v4找到。     


## 使用说明
**如果你是纯萌新建议看我B站的专栏安装：https://www.bilibili.com/read/cv26348023**         

### 安装与使用文档      
[**安装文档**](docs/installation.md)       
[**使用文档**](docs/usage.md)     

[**服务器录播示例**](https://github.com/SmallPeaches/DanmakuRender/discussions/368)

### 可选参数
程序运行时可以指定以下参数
- `--config` 指定配置文件夹，默认configs
- `--version` 查看版本号
- `--skip_update` 跳过版本检查

## 更多
感谢 THMonster/danmaku, wbt5/real-url, ForgQi/biliup, ForgQi/stream-gears 的工作。     
出现问题欢迎大家提issue讨论。       

**本程序仅供研究学习使用！**
