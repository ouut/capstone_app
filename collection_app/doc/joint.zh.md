## 🎨 ARKit 全身 91 骨骼节点全景图

```
                                  [head_joint] (头顶)
                                       |
                   [left_eye]------[nose_joint]------[right_eye]
                       |               |                 |
               [left_eyeLowerLid]  [jaw_joint]   [right_eyeLowerLid]
               [left_eyeUpperLid]      |         [right_eyeUpperLid]
               [left_eyeball]      [chin_joint]  [right_eyeball]
                                       |
                                 [neck_4_joint]
                                       |
                                 [neck_3_joint]
                                       |
                                 [neck_2_joint]
                                       |
                                 [neck_1_joint] (脖子根部)
                                       |
                                 [spine_7_joint]
                                       |
          +----------------------------+----------------------------+
          |                            |                            |
  [left_shoulder_1]             [spine_6_joint]             [right_shoulder_1]
          |                            |                            |
    [left_arm_joint]            [spine_5_joint]             [right_arm_joint]
          |                            |                            |
   [left_forearm_joint]         [spine_4_joint]            [right_forearm_joint]
          |                            |                            |
   [left_hand_joint]            [spine_3_joint]            [right_hand_joint]
          |                            |                            |
   ( 🖐️ 参见左手详解 )         [spine_2_joint]             ( 🖐️ 参见右手详解 )
                                       |
                                [spine_1_joint]
                                       |
                             +---------+---------+
                             |                   |
                       [hips_joint]              |
                             |                   |
                             +---------+---------+
                                       |
                                 [root] (骨盆核心原点 0,0,0)
                                       |
          +----------------------------+----------------------------+
          |                                                         |
   [left_upLeg_joint] (左大腿根)                             [right_upLeg_joint] (右大腿根)
          |                                                         |
    [left_leg_joint] (左膝盖)                                 [right_leg_joint] (右膝盖)
          |                                                         |
   [left_foot_joint] (左脚踝)                                [right_foot_joint] (右脚踝)
          |                                                         |
   [left_toes_joint] (左脚趾)                                [right_toes_joint] (右脚趾)
          |                                                         |
  [left_toesEnd_joint] (左脚尖)                             [right_toesEnd_joint] (右脚尖)

```

---

## 🖐️ 左右手精细手指节点详解（鼠标与键盘控制核心）

在你的数据中，左右手各自延伸出了 5 根手指，每根手指包含 4 个精细关节。它们的拓扑结构一模一样。我们以 **`right_hand_joint`（右手）** 为例展开：

```
                              [right_hand_joint] (右手腕)
                                       |
       +-------------------+-----------+-----------+-------------------+
       |                   |           |           |                   |
[right_handThumb]   [right_handIndex] [right_handMid] [right_handRing] [right_handPinky]
  (大拇指)               (食指)         (中指)       (无名指)       (小拇指)
       |                   |           |           |                   |
    [Start]             [Start]     [Start]     [Start]             [Start]
       |                   |           |           |                   |
   [_1_joint]          [_1_joint]  [_1_joint]  [_1_joint]          [_1_joint]
       |                   |           |           |                   |
   [_2_joint]          [_2_joint]  [_2_joint]  [_2_joint]          [_2_joint]
       |                   |           |           |                   |
   [_3_joint]          [_3_joint]  [_3_joint]  [_3_joint]          [_3_joint]
       |                   |           |           |                   |
     [End]               [End]       [End]       [End]               [End]
   (大拇指尖)          (食指尖)    (中指尖)    (无名指尖)          (小拇指尖)

```

---

## 💡 拿着这张图，怎么在代码里看懂你的数据？

当你把数据灌进 Unity 或 Python 时，这张“图”能帮你建立强烈的**空间几何直觉**：

1. **父子联动（Forward Kinematics）：**
如果你把 `root` 往上平移了 10 厘米，那么由于层级关系，上面所有的 `spine`、`head`、`hand` 都会自动跟着往上平移 10 厘米。因为它们的坐标是相对父节点的！
2. **计算关节夹角（比如做八段锦/深蹲）：**
如果你想知道玩家有没有**弯曲手臂**，你只需要从数据里抽出三个点：`left_shoulder_1_joint`、`left_arm_joint` 和 `left_forearm_joint`。用这三个 3D 坐标在数学里算一个向量夹角，就能瞬间知道玩家的手臂弯曲了多少度。
3. **相机节点（`camera`）：**
在你数据的最后一列看到了 `camera`。这代表 **iPhone 手机本身在空间中的位置**。用 `root` 的坐标减去 `camera` 的坐标，你的游戏就能立马知道：**玩家当前距离手机屏幕到底有多远**，从而可以动态调整游戏画面的远近！