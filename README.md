# 🎓 GyanSetu AI

> **Bridging the language gap in primary classrooms** — Hindi lessons, taught in the child's mother tongue (starting with Santali).

Built by **Team Infinixor** for **Smart India Hackathon (SIH) 2026**.

---

## 📌 Problem

Many tribal-area primary classrooms have teachers who teach in Hindi while students speak a different home language such as Santali.

- Only **23%** of Grade 1 children understand Hindi *(UNESCO PALASH, 2024 — 8,244 schools surveyed)*.
- Teachers often lack fluency in the students' tribal language.
- Santali and other tribal languages have very few digital NLP resources.
- Connectivity and devices in these schools are limited.

## 💡 Solution

GyanSetu AI helps teachers teach primary students in their **familiar mother tongue**. It translates Hindi lessons into languages like Santali and generates supporting audio, activities, worksheets, flashcards and assessments.

### ✨ Key Features

| Feature | Description |
|---|---|
| 🧑‍🏫 **Mother-Tongue Teaching Assistant** | Helps Hindi-medium teachers deliver lessons in Santali without prior language training |
| 🎙️ **Real-Time Voice Translation** | Hindi ↔ Santali classroom communication via speech and translated audio |
| 📦 **AI Learning Pack Generator** | Turns one lesson into bilingual content, activities, worksheets, assessments and flashcards |
| 📴 **Offline-First Classroom** | Download a lesson pack once; reuse lessons, activities, audio and resources offline |
| 📱 **Low-Cost Device Ready** | Designed for resource-constrained Android devices and low-connectivity classrooms |

## 🔄 How It Works

1. **Teacher** logs in / signs up
2. Selects **Class → Subject → Lesson / Topic**
3. Taps **Generate**
4. AI creates a learning pack: **Audio, Activities, Flashcards, Assessments, Worksheets**
5. Pack is saved and **downloaded** for use
6. **Real-time / offline classroom** with AI translation (Hindi ↔ Santali)
7. **Students** listen, do activities, practice with flashcards and attempt assessments

## 🧱 Tech Stack

| Layer | Technologies |
|---|---|
| **Frontend** | Flutter, Dart, Android SDK |
| **Backend** | Python, FastAPI, REST API |
| **Databases** | Local Storage, PostgreSQL, Supabase |
| **Core** | Rust |
| **AI & Translation** | Lingua.direct API, IndicTrans2, Gemini API (+ Ollama) |
| **Speech** | AI4Bharat IndicVoices / Adi Vani, WAVE processing |
| **Optimization** | ONNX Runtime, INT8 quantization |
| **Storage** | Firebase Storage / Google Drive |

### System Flow

```
Teacher → Backend Processing → Storage & Delivery
              │                      │
              ├─ Extract lesson      ├─ Save to PostgreSQL
              ├─ Translate to Santali├─ Store files
              └─ Generate pack       └─ Create/Download pack (Zip)
                                         │
              Real-time Classroom ◄──────┤
              Offline Classroom   ◄──────┤
              Student Learning    ◄──────┘
```

## 🌱 Impact & Benefits

- **Language Inclusion** — bridges the gap between Hindi-medium teachers and tribal-language students
- **Teacher Empowerment** — translation, audio and ready-to-use resources without prior fluency
- **Access to Resources** — one lesson becomes translated content, activities, flashcards, worksheets and assessments
- **Offline Continuity** — downloaded packs work without internet
- **Social:** inclusive multilingual classrooms
- **Educational:** better comprehension, FLN support for foundational literacy & numeracy
- **Technological:** multilingual translation and Hindi ↔ Santali voice interaction

## ⚠️ Challenges & Strategies

| Challenge | Strategy |
|---|---|
| Low-resource language data | Hindi–Santali datasets + pretrained IndicTrans2; Lingua.direct API tested and integrated |
| Voice & latency | Lightweight, optimized audio pipeline for near-instant, low-latency response |
| Translation accuracy | Lesson-aware prompts, curated content and human/community validation before deployment |

## 🚀 Feasibility & Scalability

- **Economic:** open-source AI/NLP and reusable packs reduce recurring content and connectivity costs
- **Long-term value:** each lesson becomes a reusable digital pack
- **Scalable:** extendable to Ho, Mundari and other languages, classes and subjects
- **Large user base:** relevant across tribal and multilingual primary classrooms

## ⚙️ Getting Started

```bash
# Clone the repository
git clone <your-repo-url>
cd gyansetu-ai

# Backend
cd backend
python -m venv venv
source venv/bin/activate        # Windows: venv\Scripts\activate
pip install -r requirements.txt
uvicorn main:app --reload

# Frontend
cd ../frontend
flutter pub get
flutter run
```

Create a `.env` file in `backend/`:

```env
LINGUA_DIRECT_API_KEY=your_key
GEMINI_API_KEY=your_key
DATABASE_URL=postgresql://user:pass@host:5432/db
SUPABASE_URL=your_url
SUPABASE_KEY=your_key
```

## 📁 Suggested Structure

```
gyansetu-ai/
├── backend/        # FastAPI services, translation & pack generation
├── frontend/       # Flutter app
├── models/         # IndicTrans2 / ONNX optimized models
├── docs/           # Presentation, diagrams, screenshots
└── README.md
```

## 📚 References

- [AI4Bharat IndicTrans2](https://github.com/AI4Bharat/IndicTrans2) · [paper](https://arxiv.org/abs/2305.16307)
- [AI4Bharat IndicVoices](https://huggingface.co/datasets/ai4bharat/IndicVoices) · [GitHub](https://github.com/AI4Bharat/IndicVoices) · [IndicVoices-R](https://github.com/AI4Bharat/IndicVoices-R)
- [Adi Vaani — Ministry of Tribal Affairs](https://adivaani.tribal.gov.in/)
- [Lingua.direct AI](https://www.lingua.direct/)

## 👥 Team

**Team Infinixor** — Smart India Hackathon 2026


