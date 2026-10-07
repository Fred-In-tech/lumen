# Model licenses

On-device model weights used by Lumen. Every row must be commercially usable **including its
training data**. Add a row before a model ships, and pin its SHA-256 in
`packages/lumen_core/lib/src/vision/` (the model manifest); unpinned or mismatching files are
refused at load. Review and rejected candidates: `docs/research/03-browser-ai-tools.md` §8 and
`docs/research/07-portrait-retouch-tech.md` §7.2.

Downloaded 2026-10-03 (user-approved). Dev copies live in the git-ignored `.dev_models/`;
before launch, mirror every file to our own CDN at a versioned path (same hash).

| Model | Use | Ships as | Source URL | License | SHA-256 | Bytes | Commercial OK | Training-data note |
|---|---|---|---|---|---|---|---|---|
| BlazeFace short-range (from `face_landmarker.task`) | face detection, near faces | bundled `app/assets/models/blaze_face_short_range.tflite` | https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/latest/face_landmarker.task | Apache-2.0 (model card) | `b4578f35940bf5a1a655214a1cce5cab13eba73c1297cd78e1a04c2380b0152f` | 229,746 | Yes | Google-collected images |
| FaceMesh V2 landmarks (from `face_landmarker.task`) | 478 face landmarks incl. iris | bundled `app/assets/models/face_landmarks_detector.tflite` | same `.task` bundle (sha `64184e229b263107bc2b804c6625db1341ff2bb731874b0bcc2fe6544e0bc9ff`, 3,758,596 B) | Apache-2.0 (model card) | `c7d54204ce0448474c7f3fa9af494787c0965cbdd6f20fc72867e43046bd43d5` | 2,553,590 | Yes | Google-captured smartphone images, 17 regions |
| BlazeFace full-range | face detection, group/wide shots | bundled `app/assets/models/blaze_face_full_range.tflite` | https://storage.googleapis.com/mediapipe-models/face_detector/blaze_face_full_range/float16/latest/blaze_face_full_range.tflite | Apache-2.0 (family card; confirm full-range card before launch) | `3698b18f063835bc609069ef052228fbe86d9c9a6dc8dcb7c7c2d69aed2b181b` | 1,083,786 | Yes | Google-collected images |
| Selfie Multiclass 256×256 | skin / hair / clothes / accessories parsing per face tile (retouch skin masks, cached per photo in `assets/<id>/cache/parsing.bin`, local only); AI masks | download on first Portrait use or AI mask (never by export or Auto Retouch) | https://storage.googleapis.com/mediapipe-models/image_segmenter/selfie_multiclass_256x256/float32/latest/selfie_multiclass_256x256.tflite | Apache-2.0 (model card) | `c6748b1253a99067ef71f7e26ca71096cd449baefa8f101900ea23016507e0e0` | 16,371,837 | Yes | Google; fairness-evaluated across Monk skin tones 1–10 |
| MI-GAN 512 Places2 (LiteRT fp16) | object removal | download on first Remove | https://huggingface.co/litert-community/MI-GAN-512-Places2-LiteRT/resolve/main/migan_fp16.tflite | MIT (code + weights) | `ef53f8dca69e5ce29629441128322c4d9a0a527b2a043703e0ab497f2463c25f` | 16,312,640 | Yes, **legal note** | Trained on Places2: confirm dataset terms with counsel before selling |
| Hair Segmenter | flyaway hair (deferred) | not shipped | https://storage.googleapis.com/mediapipe-models/image_segmenter/hair_segmenter/float32/latest/hair_segmenter.tflite | Apache-2.0 | `2628cf3ce5f695f604cbea2841e00befcaa3624bf80caf3664bef2656d59bf84` | 781,618 | Yes | Needs MediaPipe custom ops (MaxPoolingWithArgmax2D) that flutter_litert 3.9.3 lacks |

Never ship: InsightFace/SCRFD weights, CelebAMask-HQ- or LaPa-trained face parsers (incl.
"MIT-tagged" BiSeNet ports), FFHQR-trained retouch nets, BRIA RMBG, or any non-commercial
model. Never compute or store face embeddings.

Verified tensor contracts: `app/test/ai/ondevice/litert_model_contract_test.dart`.
