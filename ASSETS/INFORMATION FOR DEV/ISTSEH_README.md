# ISTSEH / استصح

## Project Overview

**ISTSEH / استصح** is an Arabic-first medication management and safety application designed mainly for elderly users and their caregivers in Kuwait and the GCC. The core idea is to help families manage medication routines clearly, safely, and consistently through a mobile app that supports reminders, caregiver access, medication search, interaction checking, allergies, conditions, and AI-assisted medication understanding.

ISTSEH is not intended to be only a reminder app. The long-term direction is to become a localized medication intelligence platform that combines structured medication data, patient-specific safety checks, caregiver workflows, and Arabic-friendly usability.

The product is built around three major values:

- **Safety:** reduce medication mistakes, missed doses, unsafe combinations, and unverified drug entries.
- **Simplicity:** make the app usable for elderly Arabic-speaking users without overwhelming screens.
- **Family care:** allow caregivers to support patients through secure patient/caregiver connections.

---

## The Problem

Medication management is difficult, especially for elderly patients who may take multiple medicines, have chronic conditions, or rely on family members for care. Common problems include:

- Forgetting medication times.
- Taking medicine at the wrong time.
- Misunderstanding dosage instructions.
- Combining medicines that may interact.
- Not tracking allergies or medical conditions.
- Caregivers not having a clear view of the patient’s medication routine.
- Medication apps being too complex, English-heavy, or not designed for GCC family caregiving.

ISTSEH aims to solve this by creating a medication companion that is clear, localized, caregiver-friendly, and safer than a basic reminders app.

---

## Target Users

ISTSEH is designed for:

- Elderly patients who need help managing medications.
- Caregivers or family members who support patients.
- Patients with multiple medications, allergies, or chronic conditions.
- Arabic-speaking users who need a simpler and more familiar medication app experience.
- GCC families where caregiving is often shared between relatives.

---

## Core Product Idea

ISTSEH helps users:

- Add and manage medications.
- Create medication schedules.
- Track dose events.
- Receive medication reminders.
- Store allergies and medical conditions.
- Allow caregivers to connect to patients securely.
- Search for medications.
- Check possible medication interactions.
- Use AI-assisted medication intelligence.
- Use camera/image recognition to identify medicines.
- Move toward a verified local medication dataset for faster and safer search.

The strongest product direction is to make ISTSEH a trusted medication safety layer for families, not just a notification app.

---

## Main Features

### 1. Patient and Caregiver Modes

ISTSEH supports two main user contexts:

- **Patient mode:** the patient manages or views their own medications and health profile.
- **Caregiver mode:** a family member or caregiver can connect to a patient and help manage their medication routine.

The system supports:

- Patient/caregiver relationships.
- Active patient selection.
- Session persistence.
- Family care-code connection.
- Secure access control.

This turns the app into a family-care platform instead of a single-user medication tracker.

---

### 2. Care Code System

A care-code system allows caregivers to connect to patients.

The system was hardened for security. Instead of storing care codes in plain text, the backend now uses:

- Hashed care codes.
- SHA-256 hashing with a pepper.
- Short expiry windows.
- Failed attempt tracking.
- Locked state after repeated failures.
- Generic error messages for redemption failures.
- Atomic redemption through a database RPC function.
- Audit logging with safe fingerprints instead of exposing plain codes.

This makes the connection flow safer and reduces the risk of code guessing, reuse, or leakage.

---

### 3. Medication Management

ISTSEH includes the foundation for medication management through the iOS app and Supabase backend.

Medication-related capabilities include:

- Adding medications.
- Managing patient medications.
- Connecting medications to schedules.
- Tracking dose events.
- Searching medication information.
- Supporting future verified medication datasets.

Medication management is one of the main pillars of the app because it connects reminders, interaction checking, patient profiles, and caregiver visibility.

---

### 4. Medication Scheduling and Dose Tracking

The backend includes tables for:

- `medication_schedules`
- `medication_dose_events`

These support future and current flows such as:

- Daily medication timeline.
- Dose reminders.
- Missed dose tracking.
- Taken/skipped dose events.
- Caregiver visibility.
- Adherence insights.

The goal is not only to remind users, but to create a reliable medication history.

---

### 5. Allergies and Conditions

ISTSEH includes a medical profile layer for allergies and conditions.

Implemented or verified so far:

- Patients can add allergies.
- Patients can add medical conditions.
- Allergies use soft delete through `is_active = false`.
- Conditions use `status = inactive` and `is_active = false`.
- Lifecycle events are audited.
- Caregiver authorization is checked before accessing patient data.
- Interaction checking prioritizes the authenticated patient’s allergies.

This moves ISTSEH closer to patient-specific safety instead of generic medication reminders.

---

### 6. Drug Interaction Checking

ISTSEH includes a Supabase Edge Function for interaction checking:

- `check-interactions`

The function uses external medication data and AI-assisted classification to help identify possible interaction severity.

Current severity categories include:

- High
- Medium
- Low

Current improvement areas:

- Better duplicate active ingredient detection.
- Stronger condition-drug conflict checks.
- More reliable local/offline interaction rules.
- Ensuring local safety logic never silently fails open.

The interaction engine is moving in the right direction, but it still needs additional safety hardening before it can be treated as a fully reliable medical safety system.

---

### 7. Medication Search

A major issue identified during development is that medication search needs to become much better.

Current concern:

- Search results are visually inconsistent.
- Search logic is too limited.
- Users should be able to type partial names, such as `pan`, and receive multiple relevant medication results, such as Panadol and related medicines.

Planned direction:

- Build a local medication dataset.
- Normalize medication names and ingredients.
- Support prefix and fuzzy search.
- Return multiple clean results.
- Improve medication result card design.
- Make search faster and less dependent on live APIs.

This is one of the biggest architectural pivots in the project.

---

### 8. Camera / Image-to-Drug Flow

ISTSEH includes an image-based medication identification concept through:

- `image-to-drug`

The idea is that users can take a photo of a medicine package or pill, and the system can attempt to identify it.

Important safety concern:

AI may misidentify a medicine. Because of that, AI-generated results should not be saved directly without user confirmation.

Recommended flow:

1. User scans or uploads medication image.
2. AI suggests possible identification.
3. App clearly labels the result as unverified.
4. User confirms or edits the result.
5. Only then is the medication saved.

This prevents hallucinated or low-confidence AI output from becoming trusted medication data.

---

### 9. AI Drug Intelligence

ISTSEH uses AI-assisted flows through functions such as:

- `drug-intel`
- `image-to-drug`
- `check-interactions`

AI can help summarize medication information, classify severity, or interpret images, but it should not become the trusted source of truth by itself.

The safer architecture is:

- Official medication data = trusted base layer.
- AI summaries = explanation/helper layer.
- User confirmation = required for risky outputs.
- Audit logs = record sensitive actions.

This separation is important for long-term safety and credibility.

---

## Backend Implementation

ISTSEH uses **Supabase** as the backend.

Backend responsibilities include:

- Authentication.
- Patient/caregiver relationships.
- Family care codes.
- Medication records.
- Medication schedules.
- Dose events.
- Allergies.
- Conditions.
- Interaction checking.
- Audit logging.
- Device sessions.
- Drug source caching.
- AI summary caching.
- Row Level Security policies.

A backend foundation migration added major tables such as:

- `audit_logs`
- `patient_devices`
- `interaction_rules`
- `patient_allergies`
- `patient_conditions`
- `drug_source_cache`
- `drug_ai_summary_cache`
- `medication_schedules`
- `medication_dose_events`

Security improvements include:

- Tighter RLS policies.
- Safer caregiver access.
- Removal of hard deletes for medical data.
- Soft delete patterns for allergies and conditions.
- Restricted public cache access.
- Authenticated access for sensitive AI summary cache data.

---

## Supabase Edge Functions

The project includes or references these Supabase Edge Functions:

- `create-family-member`
- `redeem-care-code`
- `patient-medications`
- `drug-intel`
- `image-to-drug`
- `check-interactions`
- `transfer-patient`

These functions handle sensitive workflows such as:

- Creating family members.
- Redeeming care codes.
- Fetching patient medications.
- Generating drug intelligence.
- Identifying medication images.
- Checking drug interactions.
- Transferring patient context.

---

## iOS Implementation

The iOS app is built with **SwiftUI**.

Current project path:

```text
TA3AFA/MEDSAI
```

Important app areas include:

- `App`
- `Auth`
- `Settings`
- `Meds`
- `Calendar`
- `Search`
- `Utilities`
- `Services`

Supabase integration is centralized in:

```text
Services/SupabaseManager.swift
```

Important files/classes discussed during development include:

- `MediScheduleApp.swift`
- `MedViews.swift`
- `CameraCaptureView`
- `PatientSessionStore`
- `UserMedsRepo`
- `AppointmentRepo`
- `SearchHistoryRepo`
- `FamilySettingsView`
- `SettingsView`
- `AppSettings`

---

## Session Persistence

ISTSEH includes work around patient/caregiver session persistence.

Legacy UserDefaults keys included:

- `deviceToken`
- `patientUserId`
- `activePatientId`
- `activePatientName`
- `userRole`

The direction is to migrate these values into a cleaner session store so that the app can restore the correct context after relaunching.

Important QA scenarios:

1. Launch with old UserDefaults values and confirm normal context restoration.
2. Redeem a care code, quit, relaunch, and confirm patient mode persists.
3. As caregiver, select an active patient, quit, relaunch, and confirm selected patient persists.
4. Sign out or disconnect patient mode, relaunch, and confirm session clears.
5. Confirm old legacy keys are removed from UserDefaults.

This is important because a medication app must remember the correct patient context reliably.

---

## UI and Branding Direction

ISTSEH has a dark medical-tech visual direction.

Core brand colors:

```text
Primary green fill: #2ECC71
Dark navy background: #1A1A2E
Green stroke: #2CA861
```

Design goals:

- Arabic-first interface.
- Elder-friendly screens.
- Consistent container colors.
- Clean search result cards.
- Calm medical-tech feeling.
- Strong visual consistency across Today, Calendar, Search, Settings, and medication screens.

Current UI issues identified:

- Search results look inconsistent.
- Containers across pages use inconsistent colors.
- Some screens need final polish.
- Search result presentation needs to feel more professional.
- The app should have one shared card/container design system.

The next UI goal is to create a consistent app-wide design system.

---

## Medication Dataset Strategy

A major planned improvement is to build a local medication dataset instead of relying only on live APIs.

The planned pipeline:

1. Download medication data locally.
2. Process and clean it on the development machine.
3. Normalize medication names, ingredients, dosage forms, strengths, routes, warnings, labels, and source references.
4. Structure the data for ISTSEH’s database.
5. Upload the processed data to Supabase.
6. Use it for faster and safer search inside the app.
7. Design the schema so more sources can be added later.

Benefits:

- Faster search.
- Better autocomplete.
- Less dependency on external APIs.
- More control over data quality.
- Easier support for future medication sources.
- Better foundation for Arabic localization.

---

## Architecture Direction

ISTSEH is moving toward a layered architecture:

### 1. iOS App Layer

SwiftUI screens, patient/caregiver context, medication views, calendar, search, settings, camera flow, and session management.

### 2. Supabase Backend Layer

Authentication, database tables, RLS, patient/caregiver data, schedules, dose events, allergies, conditions, and audit logs.

### 3. Edge Function Layer

Medication intelligence, interaction checking, care-code flows, image-to-drug logic, and patient medication APIs.

### 4. Medication Data Layer

Official medication source data, normalized drug records, source cache, AI summary cache, and future local medication dataset.

### 5. AI Assistance Layer

AI summaries, severity classification, medicine image interpretation, and explanation support. This layer should assist users but not replace verified medication data.

---

## Implementation Status

### Completed or Partially Completed

- SwiftUI iOS app structure.
- Supabase integration.
- Patient and caregiver model.
- Care-code connection flow.
- Secure care-code hardening.
- Patient session persistence work.
- Medication management foundation.
- Medication schedule and dose event backend tables.
- Allergies and conditions UI/backend.
- Interaction checking Edge Function.
- AI drug intelligence functions.
- Image-to-drug concept.
- Audit logging.
- RLS policy hardening.
- Brand identity direction.
- UI improvement direction.
- Medication dataset strategy.

### Still Needed

- Final UI consistency across all screens.
- Better medication search logic.
- Better medication search result design.
- Local medication dataset pipeline.
- Arabic medication instruction parsing.
- Safer image-to-drug confirmation screen.
- Duplicate active ingredient detection.
- Condition-drug conflict logic.
- Stronger local/offline interaction rules.
- Verified medication data model.
- Final marketing/ad video assets.
- Company Program deliverables such as report, presentation, financials, legal plan, booth material, and pitch script.

---

## Business and JA Company Program Fit

ISTSEH fits well as a social entrepreneurship and innovation project because it addresses a real healthcare and family-care problem.

It connects strongly to:

- Innovation and technology.
- Artificial intelligence.
- Healthcare accessibility.
- Elder care.
- Family caregiving.
- Responsible digital health.
- Social impact.

From a company-program perspective, ISTSEH already has strong material for:

- Product/service idea.
- Market research.
- Business plan.
- Digital marketing strategy.
- Company structure.
- Technical implementation.
- SDG connection.
- Pitch and presentation.
- Trade fair booth.
- Video/ad concept.

---

## One-Sentence Description

**ISTSEH is an Arabic-first medication safety and management app for elderly patients and caregivers, combining reminders, patient profiles, caregiver access, medication search, AI-assisted drug intelligence, interaction checking, and a growing plan for a verified local medication dataset.**

---

## Pitch Description

ISTSEH is a digital medication companion built for GCC families caring for elderly loved ones. It helps patients and caregivers manage medications, schedules, allergies, conditions, and safety checks from one simple Arabic-friendly app. Instead of acting only as a reminder, ISTSEH is being built as a safer medication intelligence platform, combining structured health records, caregiver connectivity, AI-assisted medicine understanding, and a future local medication database designed for faster, more reliable search and safer decision-making.

---

## Current Project Direction

The next major direction for ISTSEH is to move from a functional app prototype into a polished, safer, more scalable product.

The priorities are:

1. Finalize UI consistency.
2. Improve search behavior and design.
3. Build the local medication dataset.
4. Harden AI flows with confirmation screens.
5. Strengthen interaction and safety logic.
6. Prepare marketing visuals and demo video.
7. Complete company-program deliverables.

ISTSEH already has the bones of a serious digital health product. The next step is sharpening the claws, polishing the armor, and making the experience feel trustworthy from the first tap.
