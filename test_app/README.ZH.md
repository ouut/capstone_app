这是一份完整的技术架构与使用指南文档，详细描述了如何将 **OpenCV（视觉骨骼捕捉）** 与 **pynput（指令级键鼠驱动）** 深度结合，搭建一套“所见即所得”的体感游戏全栈测试环境。

---

# 🛠️ 体感核心：OpenCV 与 pynput 联合测试环境搭建指南

## 1. 为什么将两者结合？

在体感游戏研发的初期阶段，直接对接游戏往往会因为系统层级多、盲区不确定而导致调试效率极低。将 OpenCV 与 pynput 结合，可以打造一个**双向闭环的智能测试台**：

* **OpenCV 负责“输入侧”可视化**：实时将手机 ARKit 发来的 3D 骨骼高频数据流投影为 2D 正视、侧视、俯视图，用肉眼直接观察**空间对齐、重心漂移和信号毛刺**。
* **pynput 负责“输出侧”可视化**：在同一个 OpenCV 窗口内绘制一套**虚拟键盘与虚拟鼠标面板**。当你的几何/AI 算法判定动作触发并驱动系统键鼠时，OpenCV 窗口的虚拟键位会同步高亮。

**最终效果**：你只需站在手机前做动作，在一个黑色窗口内就能同时验证“我的身体姿态”与“最终发给游戏的按键指令”是否 100% 同步，实现免游戏打磨极致手感。

---

## 2. 联合测试环境系统架构

整个联调测试环境的数据流呈单向闭环，各模块之间异步并行运作：

```
[ 手机端 (iOS ARKit) ]
         │
         │ (1) 原始 3D 骨骼 JSON 数据 (UDP, 60 FPS)
         ▼
[ 后台 UDP 接收线程 ]
         │
         │ (2) 空间归一化 (减去Hips) + 一阶低通滤波防抖
         ▼
[ 核心算法判定层 ] ───► (3) 达到阈值 ───► [ pynput 控制器驱动层 ]
         │                                         │
         │ (4) 共享最新的数据状态 (ui_states)       │ (5) 触发系统/浏览器
         ▼                                         ▼     物理按键或鼠标
[ 前端 OpenCV 主渲染线程 (60 FPS) ] ──► [ 屏幕虚拟键盘/鼠标/3D投影 ]

```

---

## 3. 环境依赖安装

本测试环境完全跨平台（支持 Windows、macOS 驱动需开启辅助功能权限）。在终端中运行以下命令安装基础依赖：

```bash
pip install opencv-python numpy pynput

```

---

## 4. 核心闭环源码 (`joint_test_env.py`)

请直接复制以下完整源码并在本地运行。代码已内置高频 UDP 接收、NumPy 物理过滤、pynput 状态驱动以及 OpenCV 全栈看板：

```python
import cv2
import numpy as np
import socket
import json
import threading
import time
from pynput.keyboard import Key, Controller as KeyController
from pynput.mouse import Button, Controller as MouseController

# =====================================================================
# 1. 初始化全局状态、参数与 pynput 控制器
# =====================================================================
key_driver = KeyController()
mouse_driver = MouseController()

# 超参数调优区
CONFIG = {
    "filter_strength": 0.3,    # 滤波强度 (0.0无滤波，0.95强过滤)
    "deadzone_x": 0.15,        # 左右横移控制马里奥的死区（米）
    "jump_threshold_y": 0.25   # 触发跳跃的脖子腾空阈值（米）
}

# 共享状态机
system_states = {
    "fps": 0,
    "W": False, "A": False, "S": False, "D": False, "SPACE": False,
    "mouse_pos": (150, 150),   # 映射在画布中的相对鼠标位置
    "mouse_click": False,
    # 物理驱动锁，防止高频循环导致键盘疯狂抽搐连击
    "lock_A": False, "lock_D": False, "lock_SPACE": False
}

# 骨骼基础结构
smooth_joints = {
    "hips": np.array([0.0, 0.0, 0.0]), "neck": np.array([0.0, 0.5, 0.0]),
    "leftHand": np.array([-0.4, 0.2, 0.0]), "rightHand": np.array([0.4, 0.2, 0.0]),
    "leftFoot": np.array([-0.2, -0.6, 0.0]), "rightFoot": np.array([0.2, -0.6, 0.0])
}
CONNECTIONS = [
    ("hips", "neck"), ("neck", "leftHand"), ("neck", "rightHand"),
    ("hips", "leftFoot"), ("hips", "rightFoot")
]

# =====================================================================
# 2. 后台异步数据处理层（UDP接收 -> 物理过滤 -> 动作转化）
# =====================================================================
def udp_motion_receiver():
    global smooth_joints
    udp_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    udp_socket.bind(("0.0.0.0", 9999))
    
    frame_counter = 0
    last_fps_time = time.time()
    
    while True:
        try:
            data, _ = udp_socket.recvfrom(8192)
            raw_json = json.loads(data.decode('utf-8'))
            
            # 计算接收帧率
            frame_counter += 1
            if time.time() - last_fps_time >= 1.0:
                system_states["fps"] = frame_counter
                frame_counter = 0
                last_fps_time = time.time()

            # A. 空间归一化 (减去屁股坐标，锁定原点)
            hips_pos = np.array(raw_json.get("hips", [0, 0, 0]))
            
            # B. 一阶低通滤波
            alpha = 1.0 - CONFIG["filter_strength"]
            for k in smooth_joints.keys():
                if k in raw_json:
                    raw_pos = np.array(raw_json[k]) - hips_pos
                    smooth_joints[k] = alpha * raw_pos + (1.0 - alpha) * smooth_joints[k]

            # C. 动作行为判定 ──► 驱动 pynput 并在 UI 状态打卡
            execute_pynput_mapping()
            
        except Exception:
            pass

def execute_pynput_mapping():
    """ 核心手感控制算法与状态同步 """
    # 1. 提取核心控制特征量
    displacement_x = smooth_joints["hips"][0]  # 身体重心横向位移
    displacement_y = smooth_joints["neck"][1]  # 脖子垂直方向腾空位移
    r_hand = smooth_joints["rightHand"]        # 右手空间坐标

    # ---- 左右横移控制 (长按锁状态机) ----
    if displacement_x > CONFIG["deadzone_x"]:  # 右迈步
        if not system_states["lock_D"]:
            key_driver.press('d')
            system_states["lock_D"] = True
            system_states["D"] = True
    else:
        if system_states["lock_D"]:
            key_driver.release('d')
            system_states["lock_D"] = False
            system_states["D"] = False

    if displacement_x < -CONFIG["deadzone_x"]: # 左迈步
        if not system_states["lock_A"]:
            key_driver.press('a')
            system_states["lock_A"] = True
            system_states["A"] = True
    else:
        if system_states["lock_A"]:
            key_driver.release('a')
            system_states["lock_A"] = False
            system_states["A"] = False

    # ---- 垂直跳跃控制 (瞬击触发) ----
    if displacement_y > CONFIG["jump_threshold_y"]:
        if not system_states["lock_SPACE"]:
            key_driver.press(Key.space)
            key_driver.release(Key.space)
            system_states["lock_SPACE"] = True
            system_states["SPACE"] = True
    else:
        if displacement_y < 0.08: # 回落到准地面重置跳跃锁
            system_states["lock_SPACE"] = False
            system_states["SPACE"] = False

    # ---- 右手映射虚拟鼠标轨迹 (将物理 -0.5~0.5 米映射到 0~300 像素) ----
    mx = int((r_hand[0] + 0.5) * 300)
    my = int((0.5 - r_hand[1]) * 300) # Y轴反转
    system_states["mouse_pos"] = (np.clip(mx, 0, 300), np.clip(my, 0, 300))

# 启动异步数据转化层
threading.Thread(target=udp_motion_receiver, daemon=True).start()

# =====================================================================
# 3. 前端可视化渲染层（OpenCV 联合调试面板）
# =====================================================================
def draw_skeleton_projection(joints, axis_h, axis_v, title):
    """ 绘制 2D 视角投影 """
    view = np.zeros((260, 260, 3), dtype=np.uint8)
    cv2.line(view, (0, 130), (260, 130), (40, 40, 40), 1)
    cv2.line(view, (130, 0), (130, 260), (40, 40, 40), 1)
    
    SCALE = 130 # 放大映射
    def to_pt(arr):
        return (int(130 + arr[axis_h]*SCALE), int(130 - arr[axis_v]*SCALE))

    for p1, p2 in CONNECTIONS:
        cv2.line(view, to_pt(joints[p1]), to_pt(joints[p2]), (200, 200, 200), 2)
    for k, pos in joints.items():
        color = (0, 0, 255) if k == "hips" else (0, 255, 0)
        cv2.circle(view, to_pt(pos), 5, color, -1)
        
    cv2.putText(view, title, (10, 20), cv2.FONT_HERSHEY_SIMPLEX, 0.4, (0, 255, 255), 1)
    return view

def draw_ui_key(img, label, is_active, pt, size=(45, 45)):
    """ 绘制虚拟键盘按键 """
    x, y = pt
    w, h = size
    color = (0, 255, 255) if is_active else (35, 35, 35)
    thick = -1 if is_active else 2
    cv2.rectangle(img, pt, (x+w, y+h), color, thick)
    t_color = (0, 0, 0) if is_active else (150, 150, 150)
    cv2.putText(img, label, (x+12, y+28), cv2.FONT_HERSHEY_SIMPLEX, 0.5, t_color, 2)

# 创建主监控窗口
cv2.namedWindow("Motion Debug Center", cv2.WINDOW_AUTOSIZE)

def on_trackbar(val): CONFIG["filter_strength"] = val / 100.0
cv2.createTrackbar("Noise Filter", "Motion Debug Center", int(CONFIG["filter_strength"]*100), 95, on_trackbar)

# 一体化大画布初始化 (高 500, 宽 820)
canvas = np.zeros((500, 820, 3), dtype=np.uint8)

while True:
    canvas[:, :] = (15, 15, 15) # 清屏暗黑背景
    
    # A. 顶部系统状态栏
    cv2.putText(canvas, f"UDP DATA STREAM: {system_states['fps']} FPS", (20, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 0), 1)
    cv2.putText(canvas, f"ACTIVE DRIVER: pynput INTERMEDIATE", (480, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 165, 255), 1)
    cv2.line(canvas, (15, 45), (805, 45), (40, 40, 40), 1)

    # B. 渲染左侧三大 2D 姿态视窗
    front = draw_skeleton_projection(smooth_joints, 0, 1, "Front View (X-Y)")
    side  = draw_skeleton_projection(smooth_joints, 2, 1, "Side View (Z-Y)")
    
    # 拼入大画布
    canvas[70:330, 20:280] = front
    canvas[70:330, 300:560] = side

    # C. 渲染右侧 pynput 虚拟按键面板
    panel_x, panel_y = 590, 70
    cv2.putText(canvas, "pynput VIRTUAL KEYBOARD", (panel_x, panel_y - 10), cv2.FONT_HERSHEY_SIMPLEX, 0.4, (100, 100, 100), 1)
    draw_ui_key(canvas, "W", system_states["W"], (panel_x + 60, panel_y))
    draw_ui_key(canvas, "A", system_states["A"], (panel_x, panel_y + 55))
    draw_ui_key(canvas, "S", system_states["S"], (panel_x + 60, panel_y + 55))
    draw_ui_key(canvas, "D", system_states["D"], (panel_x + 120, panel_y + 55))
    
    # 空格大键
    space_color = (0, 255, 255) if system_states["SPACE"] else (35, 35, 35)
    space_thick = -1 if system_states["SPACE"] else 2
    cv2.rectangle(canvas, (panel_x, panel_y + 120), (panel_x + 165, panel_y + 155), space_color, space_thick)
    s_text_c = (0, 0, 0) if system_states["SPACE"] else (150, 150, 150)
    cv2.putText(canvas, "SPACE (JUMP)", (panel_x + 25, panel_y + 142), cv2.FONT_HERSHEY_SIMPLEX, 0.4, s_text_c, 1)

    # D. 底部鼠标虚拟轨迹雷达区
    m_radar_x, m_radar_y = 20, 360
    cv2.rectangle(canvas, (m_radar_x, m_radar_y), (m_radar_x + 540, m_radar_y + 110), (25, 25, 25), -1)
    cv2.rectangle(canvas, (m_radar_x, m_radar_y), (m_radar_x + 540, m_radar_y + 110), (40, 40, 40), 1)
    cv2.putText(canvas, "MOUSE X-TRAJECTORY RADAR", (m_radar_x + 10, m_radar_y + 20), cv2.FONT_HERSHEY_SIMPLEX, 0.4, (90, 90, 90), 1)
    
    # 绘制鼠标实时水平运动游标
    m_cursor_x = m_radar_x + int((system_states["mouse_pos"][0] / 300) * 520)
    cv2.circle(canvas, (m_cursor_x, m_radar_y + 60), 10, (0, 255, 255), -1)
    cv2.putText(canvas, f"M_X: {system_states['mouse_pos'][0]} px", (m_cursor_x - 30, m_radar_y + 90), cv2.FONT_HERSHEY_SIMPLEX, 0.35, (0, 255, 255), 1)

    # 显示核心大面板
    cv2.imshow("Motion Debug Center", canvas)

    # 监控键盘输入，按 [ESC] 键安全闭环退出
    if cv2.waitKey(1) & 0xFF == 27:
        break

cv2.destroyAllWindows()

```

---

## 5. 环境调试与手感打磨核心操作（核心实验）

进入联合测试环境后，请不要打开游戏，完全根据 OpenCV 屏幕大面板反馈进行以下三个步骤的参数打磨：

### 实验一：打磨“大区死区（Deadzone）”防误触

* **物理动作**：站在手机前自然呼吸，身体进行极其微幅的左右晃动。
* **观察目标**：看左侧 `Front View` 小人的躯干晃动，同时盯住右侧的 `A` 键和 `D` 键。
* **调校逻辑**：如果呼吸晃动时 `A` 键或 `D` 键频繁闪烁变黄，说明你的死区设小了（马里奥会原地抽搐）。去修改代码第 15 行的 `"deadzone_x"`，调大到让其完全不闪烁为止；随后做一次真正的大幅侧迈步，此时按键必须瞬间常亮。

### 实验二：打磨“跳跃空击锁（State Lock）”防止连蹦

* **物理动作**：原地轻巧起跳一次。
* **观察目标**：观察右侧 `SPACE (JUMP)` 键的亮起状态。
* **调校逻辑**：理想状态下，你跳跃一次，`SPACE` 框只能**瞬间亮起并瞬间熄灭一次**。如果它连续刷屏高亮，说明在空中下落时由于噪声二次触发了判定（马里奥会触发无限连跳连蹦）。去修改第 16 行的 `"jump_threshold_y"` 阈值调高，直到跳跃极其干净利落。

### 实验三：拖动“去噪滑块（Noise Filter）”找平衡点

* **物理动作**：将手举在半空中保持绝对静止。
* **观察目标**：观察底部的黄色的 `MOUSE X-TRAJECTORY RADAR` 指针游标。
* **调校逻辑**：拖动窗口上方的 `Noise Filter` 滑块到 `0`，你会发现游标在原地高频乱颤（硬件噪声）。慢慢将滑块向右拖动（增加低通滤波权重），直到游标完全静止不抖。注意：不要拉得过大（比如拉到 0.95），否则你挥手时游标会产生明显的跟手延迟。找到那个**既不抖动、又无延迟延迟**的甜点级参数。

---

## 6. 在线闭环与安全保障

1. **ESC 强退保障**：本系统属于全局模拟硬件输入，为防止代码陷入死循环导致物理键盘鼠标锁死，主循环捕获了键盘事件。在任何紧急情况下，只需鼠标点击 OpenCV 窗口并按下电脑的 **`ESC` 键**，整个后台 UDP 和 `pynput` 引擎将瞬间解绑、安全退出。
2. **macOS 特殊放行**：在 Mac 上运行时，若代码执行到 `key_driver.press` 却没有产生任何虚拟高亮反馈，请立即前往 `系统设置 -> 隐私与安全性 -> 辅助功能` 中，将运行此 Python 脚本的终端程序手动勾选放行。
