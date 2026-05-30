-- Fix: Add missing DELETE RLS policy for caregiver_relations.
--
-- The table has SELECT and UPDATE policies for authenticated caregivers,
-- but no DELETE policy. This causes the iOS removeFamilyMember() call
-- to silently succeed with 0 rows affected, leaving the relation intact.

CREATE POLICY "caregiver_delete_own"
  ON public.caregiver_relations
  FOR DELETE
  TO authenticated
  USING (caregiver_id = auth.uid());

-- Notify PostgREST to refresh its schema cache
NOTIFY pgrst, 'reload schema';
