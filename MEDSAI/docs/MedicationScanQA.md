# Medication Scan QA Checklist

- Upload a clear English medicine box image and confirm the top catalog candidate.
- Upload a clear Arabic package image and confirm Arabic OCR extracts name, strength, and form.
- Upload a blurry image and verify ISTSEH asks for better lighting or AI image recognition.
- Upload a low-light image and verify image-quality warnings do not crash the flow.
- Use camera capture and verify it opens the same review/analyze flow as photo upload.
- Deny camera permission and verify the app shows the permission message and photo-library option.
- Confirm a correct candidate and verify `AddLocalMedView` opens before saving.
- Edit an incorrect candidate and verify edited fields carry into the add-medication wizard.
- Trigger `Try AI Image Recognition` and verify the old `image-to-drug` fallback candidates appear.
- Save the medication and verify the existing safety check still runs before persistence.
- Verify `user_medications` stores scan metadata, structured extracted fields, and candidate snapshot.
- Verify no raw medication image or full OCR text is stored by default.
