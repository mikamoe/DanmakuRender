## 🧸 脚本
- 适用于**Debian/Ubuntu**
- 一键安装/卸载,启动/停止录制
- ~~其实Docker构建更方便~~
```bash
bash <(wget -qO- https://raw.githubusercontent.com/sillda76/DanmakuRender/refs/heads/v5/dmr.sh)
```
![脚本图片](https://github.com/sillda76/DanmakuRender/blob/v5/docs/IMG_1666.jpeg)
## 💻 安装
1. **下载并解压**  
   - 获取 `v5.zip` → 解压到 `/opt/DanmakuRender-5`
2. **安装并创建 python 虚拟环境**  
   - `apt install python3-venv` → `python3 -m venv venv`
3. **安装 pip3 及依赖**  
   - `source venv/bin/activate` → `apt install python3-pip` → `pip3 install -r requirements.txt`
4. **下载biliup-rs**
   - `目前最新版本为biliupR-v0.2.2`
5. **安装ffmpeg**  
   - `sudo apt install ffmpeg -y`
   - 所有操作完成后提示安装成功
- 所有文件的目录为
- /opt/DanmakuRender-5

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
