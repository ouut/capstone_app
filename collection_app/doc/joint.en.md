Here is the complete translation of the provided text into English:

---

## 🎨 ARKit Full-Body 91-Joint Skeleton Map

```
                                  [head_joint] (Top of Head)
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
                                 [neck_1_joint] (Base of Neck)
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
   ( 🖐️ See Left Hand Detail )  [spine_2_joint]             ( 🖐️ See Right Hand Detail )
                                       |
                                [spine_1_joint]
                                       |
                             +---------+---------+
                             |                   |
                       [hips_joint]              |
                             |                   |
                             +---------+---------+
                                       |
                                 [root] (Pelvis Center / Origin 0,0,0)
                                       |
          +----------------------------+----------------------------+
          |                                                         |
   [left_upLeg_joint] (Left Hip)                             [right_upLeg_joint] (Right Hip)
          |                                                         |
    [left_leg_joint] (Left Knee)                              [right_leg_joint] (Right Knee)
          |                                                         |
   [left_foot_joint] (Left Ankle)                            [right_foot_joint] (Right Ankle)
          |                                                         |
   [left_toes_joint] (Left Toes)                             [right_toes_joint] (Right Toes)
          |                                                         |
  [left_toesEnd_joint] (Left Toe Tips)                      [right_toesEnd_joint] (Right Toe Tips)

```

---

## 🖐️ Detailed Hand & Finger Joint Topology (Core for Mouse & Keyboard Control)

In your dataset, both the left and right hands extend into 5 fingers, with each finger containing 4 precise joints. Their topological structures are identical. Here is the expanded view using **`right_hand_joint` (Right Hand)** as the example:

```
                              [right_hand_joint] (Right Wrist)
                                       |
       +-------------------+-----------+-----------+-------------------+
       |                   |           |           |                   |
[right_handThumb]   [right_handIndex] [right_handMid] [right_handRing] [right_handPinky]
    (Thumb)             (Index)       (Middle)       (Ring)         (Pinky)
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
  (Thumb Tip)        (Index Tip)  (Middle Tip) (Ring Tip)        (Pinky Tip)

```

---

## 💡 How to Read This Data in Your Code (Spatial Geometry Intuition)

When feeding this data stream into Unity or Python, this topology diagram helps build a solid understanding of how spatial joints interact:

1. **Forward Kinematics (Parent-Child Linkage):**
If you translate the `root` upward by 10 cm, the hierarchical structure dictates that all subsequent child nodes (`spine`, `head`, `hand`, etc.) will automatically move upward by 10 cm as well. This is because their coordinates are calculated relative to their respective parent nodes.
2. **Calculating Joint Angles (e.g., for Baduanjin / Squat Detection):**
If you need to detect whether a player is **bending their arm**, you only need to pull three specific points from your data: `left_shoulder_1_joint`, `left_arm_joint`, and `left_forearm_joint`. By calculating the vector angle among these three 3D coordinates mathematically, you can instantly determine exactly how many degrees the arm is bent.
3. **The Camera Node (`camera`):**
The last entry in your data table shows the `camera`. This represents **the physical position of the iPhone itself in 3D space**. By subtracting the `camera` coordinates from the `root` coordinates, your game engine can instantly calculate exactly **how far away the user is standing from the phone screen**, allowing you to dynamically adjust the scale of your UI or game graphics!