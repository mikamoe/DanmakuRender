## 新增内容

- 新增脚本（适用于**Debian/Ubuntu**）
- 脚本支持一键安装/卸载,启动/停止录制
- ~~其实Docker构建更方便~~
```bash
bash <(wget -qO- https://raw.githubusercontent.com/sillda76/DanmakuRender/refs/heads/v5/dmr.sh)
```
![脚本图片](https://github.com/sillda76/DanmakuRender/blob/v5/IMG_1628.jpeg)
## 脚本逻辑
安装逻辑：
检查目录 -> 安装git与其他依赖 -> 克隆仓库 -> 设置虚拟环境 -> 进入虚拟环境 -> 安装python依赖 -> 安装biliup -> 完成
- 最后所有文件的目录为
- /opt/DanmakuRender-5

启动逻辑：
进入目录 -> 激活虚拟环境 -> 启动DMR -> 输出PID

停止逻辑：
查找进程 -> 停止进程 -> 提示结果

### 感谢所有开源作者
### 如果此fork影响到上游了，请给我发一封邮件
##### sillda76@gmail.com

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

### 可选参数
程序运行时可以指定以下参数
- `--config` 指定配置文件夹，默认configs
- `--version` 查看版本号
- `--skip_update` 跳过版本检查

## 更多
感谢 THMonster/danmaku, wbt5/real-url, ForgQi/biliup, ForgQi/stream-gears 的工作。     
出现问题欢迎大家提issue讨论。       

**本程序仅供研究学习使用！**
