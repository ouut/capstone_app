
# 🛠️ DIY Motion-Controlled Game Setup: OpenCV & pynput Testing Guide

## 1. What is This Project?

Imagine playing *Super Mario* not by pressing keys on your keyboard, but by **moving your body** in front of your phone's camera!

To build this, we are combining two powerful Python tools into one testing program:

* **OpenCV (The Eyes)**: This tracks your body movements. It takes the 3D skeleton data sent from your phone and draws it on your screen in real-time.
* **pynput (The Hands)**: This controls your computer. When you jump or lean in real life, `pynput` pretends to be a real keyboard and presses the keys for the game.

By putting them together in one window, you can see exactly how your body movements trigger the game keys before you even open the game!

---

## 2. How the System Works

The data flows in a continuous loop to keep the controls fast and smooth:

```
[ Your Phone (Camera) ] 
       │ 
       │ (1) Sends your 3D body joints over Wi-Fi (UDP)
       ▼
[ Background Listener ] ──► (2) Cleans up shaky data (Filtering)
       │
       ▼
[ Control Logic ] ──► (3) Decides if you moved far enough ──► [ pynput Keyboard ]
       │                                                             │
       │ (4) Updates the screen                                      │ (5) Presses Keys
       ▼                                                             ▼     for the Game
[ OpenCV Screen ] ──────────────────────────────────────────► [ High-tech Dashboard ]

```

---

## 3. Getting Started & Installation

First, you need to install the required Python tools. Open your Terminal (Mac) or Command Prompt (Windows) and type the following command:

```bash
pip install opencv-python numpy pynput

```

> **Note for Mac Users:** Because Mac is very secure, you must give permission for Python to control your keyboard. Go to `System Settings -> Privacy & Security -> Accessibility` and check the box for your Terminal or VS Code.

---

## 4. The Python Code (`motion_test_booth.py`)

Copy and paste this complete code into a Python file and run it. It creates a dummy test inside the code to show you how it works even before your phone is connected!

```python
import cv2
import numpy as np
import socket
import json
import threading
import time
from pynput.keyboard import Key, Controller as KeyController

# =====================================================================
# 1. SETTING UP THE KEYBOARD & SETTINGS
# =====================================================================
keyboard = KeyController()

# Settings you can tweak to change how sensitive the controls are
CONFIG = {
    "smoothness": 0.3,         # Changes how much we fix shaky camera data
    "lean_deadzone": 0.15,     # How far you must lean left/right to move (in meters)
    "jump_height": 0.25        # How high you must jump to trigger Spacebar (in meters)
}

# The current status of our game buttons
game_buttons = {
    "W": False, "A": False, "S": False, "D": False, "SPACE": False,
    "fps": 0,
    "lock_A": False, "lock_D": False, "lock_SPACE": False
}

# Starting positions for our virtual skeleton joints (X, Y, Z coordinates)
joints = {
    "hips": np.array([0.0, 0.0, 0.0]), "neck": np.array([0.0, 0.5, 0.0]),
    "leftHand": np.array([-0.4, 0.2, 0.0]), "rightHand": np.array([0.4, 0.2, 0.0]),
    "leftFoot": np.array([-0.2, -0.6, 0.0]), "rightFoot": np.array([0.2, -0.6, 0.0])
}

# Rules on how to connect the dots to draw the human body stick figure
BONES = [
    ("hips", "neck"), ("neck", "leftHand"), ("neck", "rightHand"),
    ("hips", "leftFoot"), ("hips", "rightFoot")
]

# =====================================================================
# 2. BACKGROUND PROCESS (Receiving Data & Pressing Keys)
# =====================================================================
def data_processor():
    # Setup a network listener on port 9999 to wait for the phone
    udp_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    udp_socket.bind(("0.0.0.0", 9999))
    
    frames = 0
    last_time = time.time()
    
    while True:
        try:
            # Receive data from the phone app
            packet, _ = udp_socket.recvfrom(8192)
            data = json.loads(packet.decode('utf-8'))
            
            # Calculate FPS (Frames Per Second) to check performance
            frames += 1
            if time.time() - last_time >= 1.0:
                game_buttons["fps"] = frames
                frames = 0
                last_time = time.time()

            # Center the skeleton so the Hips are always at (0,0,0)
            hip_offset = np.array(data.get("hips", [0, 0, 0]))
            
            # Smooth out shaking using a math formula (Low-pass filter)
            alpha = 1.0 - CONFIG["smoothness"]
            for joint_name in joints.keys():
                if joint_name in data:
                    real_pos = np.array(data[joint_name]) - hip_offset
                    joints[joint_name] = alpha * real_pos + (1.0 - alpha) * joints[joint_name]

            # Check movements and turn them into real keyboard presses!
            check_movement_triggers()
            
        except Exception:
            pass

def check_movement_triggers():
    """ This turns body movements into video game controls """
    side_lean = joints["hips"][0]  # How far left/right your hips moved
    jump_up = joints["neck"][1]    # How high your neck went up

    # ---- WALKING RIGHT (Leaning Right) ----
    if side_lean > CONFIG["lean_deadzone"]:
        if not game_buttons["lock_D"]:
            keyboard.press('d') # Holds down 'D' key on your PC
            game_buttons["lock_D"] = True
            game_buttons["D"] = True
    else:
        if game_buttons["lock_D"]:
            keyboard.release('d') # Lifts up 'D' key
            game_buttons["lock_D"] = False
            game_buttons["D"] = False

    # ---- WALKING LEFT (Leaning Left) ----
    if side_lean < -CONFIG["lean_deadzone"]:
        if not game_buttons["lock_A"]:
            keyboard.press('a') # Holds down 'A' key
            game_buttons["lock_A"] = True
            game_buttons["A"] = True
    else:
        if game_buttons["lock_A"]:
            keyboard.release('a') # Lifts up 'A' key
            game_buttons["lock_A"] = False
            game_buttons["A"] = False

    # ---- JUMPING ----
    if jump_up > CONFIG["jump_height"]:
        if not game_buttons["lock_SPACE"]:
            keyboard.press(Key.space) # Taps Spacebar once
            keyboard.release(Key.space)
            game_buttons["lock_SPACE"] = True
            game_buttons["SPACE"] = True
    else:
        if jump_up < 0.08: # When you land back down, unlock the jump
            game_buttons["lock_SPACE"] = False
            game_buttons["SPACE"] = False

# Run the network listener in the background
threading.Thread(target=data_processor, daemon=True).start()

# =====================================================================
# 3. VISUAL DISPLAY (Drawing the Dashboard with OpenCV)
# =====================================================================
def draw_stick_figure(joint_dict, title, horizontal_axis, vertical_axis):
    """ Helper to draw a 2D stick figure view """
    view = np.zeros((260, 260, 3), dtype=np.uint8)
    # Draw gray center grid lines
    cv2.line(view, (0, 130), (260, 130), (40, 40, 40), 1)
    cv2.line(view, (130, 0), (130, 260), (40, 40, 40), 1)
    
    def scale_pos(coord):
        # Scale 3D meters into 2D screen pixels
        return (int(130 + coord[horizontal_axis] * 130), int(130 - coord[vertical_axis] * 130))

    # Draw bones
    for b1, b2 in BONES:
        cv2.line(view, scale_pos(joint_dict[b1]), scale_pos(joint_dict[b2]), (200, 200, 200), 2)
    # Draw joint dots
    for name, position in joint_dict.items():
        dot_color = (0, 0, 255) if name == "hips" else (0, 255, 0) # Red hips, green everything else
        cv2.circle(view, scale_pos(position), 5, dot_color, -1)
        
    cv2.putText(view, title, (10, 20), cv2.FONT_HERSHEY_SIMPLEX, 0.4, (0, 255, 255), 1)
    return view

def draw_virtual_key(screen, text, is_active, position):
    """ Helper to draw a keyboard key on screen """
    x, y = position
    color = (0, 255, 255) if is_active else (35, 35, 35) # Yellow if pressed, dark gray if not
    fill = -1 if is_active else 2
    cv2.rectangle(screen, position, (x + 45, y + 45), color, fill)
    text_color = (0, 0, 0) if is_active else (150, 150, 150)
    cv2.putText(screen, text, (x + 14, y + 28), cv2.FONT_HERSHEY_SIMPLEX, 0.5, text_color, 2)

# Create the window
cv2.namedWindow("Motion Debug Center", cv2.WINDOW_AUTOSIZE)

def slider_callback(val): CONFIG["smoothness"] = val / 100.0
cv2.createTrackbar("Anti-Shake", "Motion Debug Center", int(CONFIG["smoothness"]*100), 95, slider_callback)

# Main screen size (Height: 400, Width: 820)
dashboard = np.zeros((400, 820, 3), dtype=np.uint8)

print("Setup Complete! Waiting for UDP data on port 9999...")

while True:
    dashboard[:, :] = (15, 15, 15) # Refresh background to dark gray
    
    # 1. Header Text
    cv2.putText(dashboard, f"PHONE CAMERA FEED: {game_buttons['fps']} FPS", (20, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 0), 1)
    cv2.putText(dashboard, "DRIVER STATUS: PYNPUT ACTIVE", (480, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 165, 255), 1)
    cv2.line(dashboard, (15, 45), (805, 45), (40, 40, 40), 1)

    # 2. Draw Stick Figures (Front View & Side View)
    front_view = draw_stick_figure(joints, "Front View (X-Y)", 0, 1)
    side_view  = draw_stick_figure(joints, "Side View (Z-Y)", 2, 1)
    dashboard[70:330, 20:280] = front_view
    dashboard[70:330, 300:560] = side_view

    # 3. Draw Virtual Keyboard Layout
    kx, ky = 590, 90
    cv2.putText(dashboard, "VIRTUAL KEYBOARD", (kx, ky - 15), cv2.FONT_HERSHEY_SIMPLEX, 0.4, (100, 100, 100), 1)
    draw_virtual_key(dashboard, "W", game_buttons["W"], (kx + 60, ky))
    draw_virtual_key(dashboard, "A", game_buttons["A"], (kx, ky + 55))
    draw_virtual_key(dashboard, "S", game_buttons["S"], (kx + 60, ky + 55))
    draw_virtual_key(dashboard, "D", game_buttons["D"], (kx + 120, ky + 55))
    
    # Draw Spacebar
    space_color = (0, 255, 255) if game_buttons["SPACE"] else (35, 35, 35)
    space_fill = -1 if game_buttons["SPACE"] else 2
    cv2.rectangle(dashboard, (kx, ky + 120), (kx + 165, ky + 155), space_color, space_fill)
    s_txt_color = (0, 0, 0) if game_buttons["SPACE"] else (150, 150, 150)
    cv2.putText(dashboard, "SPACEBAR (JUMP)", (kx + 18, ky + 142), cv2.FONT_HERSHEY_SIMPLEX, 0.4, s_txt_color, 1)

    # Footer Instructions
    cv2.putText(dashboard, "Press [ESC] on keyboard to safely close this window.", (20, 375), cv2.FONT_HERSHEY_SIMPLEX, 0.4, (80, 80, 80), 1)

    # Update the window frame
    cv2.imshow("Motion Debug Center", dashboard)

    # Safety feature: Press Esc to stop the program instantly
    if cv2.waitKey(16) & 0xFF == 27:
        break

cv2.destroyAllWindows()

```

---

## 5. How to Test Your Code (The Science Lab Part)

Once the window opens, you can test how well your system responds by doing these experiments:

### 🧪 Experiment 1: The "No-Accident" Test (Deadzone Tweak)

* **What to do**: Stand completely still in front of the camera, or just breathe normally.
* **What to look for**: Watch the `A` and `D` virtual keys on screen.
* **How to fix it**: If the keys flash yellow while you are just standing still, it means the system is *too* sensitive (Mario will glitch out!). Go to line 13 and increase `"lean_deadzone"` (e.g., change `0.15` to `0.22`) until the buttons stay gray when you stand still, but light up instantly when you take a big step to the side.

### 🧪 Experiment 2: The "Anti-Bounce" Test (Jump Lock)

* **What to do**: Do one single, quick jump.
* **What to look for**: Watch the `SPACEBAR` key on the dashboard.
* **How to fix it**: Ideally, it should flash yellow exactly **once** and turn off immediately when you land. If it blinks multiple times from one single jump, your character will double-jump by accident. Go to line 14 and increase the `"jump_height"` threshold so it only triggers at the highest point of your jump.

### 🧪 Experiment 3: The Jitter Clean-up

* **What to do**: Keep your hand perfectly still in the air.
* **What to look for**: Look at the green dots on the stick figure screen. Are they vibrating slightly? That's camera noise.
* **How to fix it**: Use your mouse to drag the **"Anti-Shake"** slider at the top of the window to the right. Watch how the vibration disappears and the movement becomes smooth. Don't slide it too far right, or your movements will feel laggy in the game!

---

## 6. Safety Features

* **Emergency Brake**: Because this program mimics a real keyboard, if something goes wrong it might type uncontrollably. We built an emergency brake: simply click on the OpenCV window and press the **`ESC` key** on your real keyboard. It will immediately shut down the entire system safely.
