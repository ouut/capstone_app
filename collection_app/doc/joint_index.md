# ARKit Body Skeleton — Joint Index → Name Mapping

91 joints, in the exact order from `ARSkeletonDefinition.jointNames` (verified from recorded CSV).  
Each joint = 28 bytes: `[x, y, z, qx, qy, qz, qw]` (7× float32 LE).

## Full Index Table

```
  0  root
  1  hips_joint
  2  left_upLeg_joint
  3  left_leg_joint
  4  left_foot_joint
  5  left_toes_joint
  6  left_toesEnd_joint
  7  right_upLeg_joint
  8  right_leg_joint
  9  right_foot_joint
 10  right_toes_joint
 11  right_toesEnd_joint
 12  spine_1_joint
 13  spine_2_joint
 14  spine_3_joint
 15  spine_4_joint
 16  spine_5_joint
 17  spine_6_joint
 18  spine_7_joint
 19  left_shoulder_1_joint
 20  left_arm_joint
 21  left_forearm_joint
 22  left_hand_joint
 23  left_handIndexStart_joint
 24  left_handIndex_1_joint
 25  left_handIndex_2_joint
 26  left_handIndex_3_joint
 27  left_handIndexEnd_joint
 28  left_handMidStart_joint
 29  left_handMid_1_joint
 30  left_handMid_2_joint
 31  left_handMid_3_joint
 32  left_handMidEnd_joint
 33  left_handPinkyStart_joint
 34  left_handPinky_1_joint
 35  left_handPinky_2_joint
 36  left_handPinky_3_joint
 37  left_handPinkyEnd_joint
 38  left_handRingStart_joint
 39  left_handRing_1_joint
 40  left_handRing_2_joint
 41  left_handRing_3_joint
 42  left_handRingEnd_joint
 43  left_handThumbStart_joint
 44  left_handThumb_1_joint
 45  left_handThumb_2_joint
 46  left_handThumbEnd_joint
 47  neck_1_joint
 48  neck_2_joint
 49  neck_3_joint
 50  neck_4_joint
 51  head_joint
 52  jaw_joint
 53  chin_joint
 54  left_eye_joint
 55  left_eyeLowerLid_joint
 56  left_eyeUpperLid_joint
 57  left_eyeball_joint
 58  nose_joint
 59  right_eye_joint
 60  right_eyeLowerLid_joint
 61  right_eyeUpperLid_joint
 62  right_eyeball_joint
 63  right_shoulder_1_joint
 64  right_arm_joint
 65  right_forearm_joint
 66  right_hand_joint
 67  right_handIndexStart_joint
 68  right_handIndex_1_joint
 69  right_handIndex_2_joint
 70  right_handIndex_3_joint
 71  right_handIndexEnd_joint
 72  right_handMidStart_joint
 73  right_handMid_1_joint
 74  right_handMid_2_joint
 75  right_handMid_3_joint
 76  right_handMidEnd_joint
 77  right_handPinkyStart_joint
 78  right_handPinky_1_joint
 79  right_handPinky_2_joint
 80  right_handPinky_3_joint
 81  right_handPinkyEnd_joint
 82  right_handRingStart_joint
 83  right_handRing_1_joint
 84  right_handRing_2_joint
 85  right_handRing_3_joint
 86  right_handRingEnd_joint
 87  right_handThumbStart_joint
 88  right_handThumb_1_joint
 89  right_handThumb_2_joint
 90  right_handThumbEnd_joint
```

## Group Summary

| Group | Indices | Count |
|-------|---------|-------|
| Root & Hips | 0–1 | 2 |
| Legs (L→R) | 2–11 | 10 |
| Spine | 12–18 | 7 |
| Left Arm & Hand | 19–46 | 28 |
| Neck & Head | 47–62 | 16 |
| Right Arm & Hand | 63–90 | 28 |

## Hierarchy (skeleton order)

```
root (0)
├── hips_joint (1)
│   ├── left_upLeg_joint (2)
│   │   └── left_leg_joint (3)
│   │       └── left_foot_joint (4)
│   │           └── left_toes_joint (5)
│   │               └── left_toesEnd_joint (6)
│   ├── right_upLeg_joint (7)
│   │   └── ... right_toesEnd_joint (11)
│   └── spine_1_joint (12)
│       └── ... spine_7_joint (18)
│           ├── left_shoulder_1_joint (19)
│           │   └── left_arm_joint (20)
│           │       └── left_forearm_joint (21)
│           │           └── left_hand_joint (22)
│           │               ├── left_handIndex* (23–27)
│           │               ├── left_handMid* (28–32)
│           │               ├── left_handPinky* (33–37)
│           │               ├── left_handRing* (38–42)
│           │               └── left_handThumb* (43–46)
│           ├── neck_1_joint (47)
│           │   └── ... neck_4_joint (50)
│           │       └── head_joint (51)
│           │           ├── jaw_joint (52)
│           │           ├── chin_joint (53)
│           │           ├── left_eye* (54–57)
│           │           ├── nose_joint (58)
│           │           └── right_eye* (59–62)
│           └── right_shoulder_1_joint (63)
│               └── ... right_handThumbEnd_joint (90)
```

## Binary Layout (per joint, 28 bytes)

```
Offset  Size    Type      Field
0       4       float32   position.x
4       4       float32   position.y
8       4       float32   position.z
12      4       float32   rotation.x (quaternion)
16      4       float32   rotation.y
20      4       float32   rotation.z
24      4       float32   rotation.w
```

## Camera Row

The final 28-byte block after all 91 joints is the camera pose (same float32×7 format).

---

## CSV vs Binary (Network) — Data Comparison

Both formats share the **same source** (`joints` array from `ARSkeletonDefinition.jointNames`), same joint order, and now both respect the FPS throttle.

| | CSV | Binary (TCP/UDP/WS) |
|---|---|---|
| Joint names | ✅ string per row | ❌ implicit by index |
| Subject ID | ❌ only in filename | ✅ 32B header |
| Session Note | ❌ only in filename | ✅ 32B header |
| Timestamp | ✅ `frame.timestamp` (Double) | ✅ 8B Double |
| Frame index | ✅ `frame.frameIndex` (Int) | ✅ 4B UInt32 |
| Camera pose | ✅ row with name `camera` | ✅ trailing 28B block |
| Per-frame size | ~7 KB (text) | 2652 B (binary) |
| Numeric precision | `%.4f` (6 significant digits) | float32 (7 significant digits) |
| Joint count | varies by row count | fixed 91 |

### Binary payload structure (2652 bytes total)

```
Offset   Size   Field
0         8     timestamp (float64 LE)
8         4     frame_index (uint32 LE)
12       32     subject_id (UTF-8, null-padded)
44       32     session_note (UTF-8, null-padded)
76     2548     joints (91 × 28 bytes, float32×7 each)
2624     28     camera (float32×7)
```

TCP adds a 4-byte big-endian length prefix (2656 bytes framed).  
WebSocket adds a 1-byte type tag `0x01` before the payload (2653 bytes framed).  
UDP sends the raw 2652-byte payload directly.
