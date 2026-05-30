-- Family-member management performance and active-list filtering.
-- Care codes remain temporary invites; caregiver_relations remains the
-- durable caregiver-to-patient relationship.

create index if not exists caregiver_relations_caregiver_status_idx
on public.caregiver_relations(caregiver_id, status);

create index if not exists caregiver_relations_patient_idx
on public.caregiver_relations(patient_id);

create index if not exists care_codes_patient_caregiver_status_expires_idx
on public.care_codes(patient_id, caregiver_id, status, expires_at);

create index if not exists device_sessions_user_id_idx
on public.device_sessions(user_id);

notify pgrst, 'reload schema';
