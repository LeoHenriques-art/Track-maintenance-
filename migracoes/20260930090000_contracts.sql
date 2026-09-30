-- Contratos e orçamento: cadastro dos contratos (prestador, periodicidade,
-- valor da prestação, vigência, situação) e a sua distribuição por centro de
-- custo. Substitui os mapas "Custos Mensais Contratados / Orçamento".
-- Aplicar depois de 20260929090000_fuel_readings.sql.

CREATE TABLE public.contracts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  -- Departamento responsável (ex.: DGP, DSGA).
  department TEXT NOT NULL,
  service TEXT NOT NULL,
  supplier TEXT NOT NULL,
  -- Número de prestações por ano sai da periodicidade.
  periodicity TEXT NOT NULL CHECK (periodicity IN
    ('Mensal', 'Bimestral', 'Trimestral', 'Quadrimestral', 'Semestral', 'Anual')),
  installment_value NUMERIC NOT NULL CHECK (installment_value >= 0),
  start_date DATE,
  end_date DATE,
  status TEXT NOT NULL DEFAULT 'Activo' CHECK (status IN ('Activo', 'Suspenso', 'Terminado')),
  -- Setor da plataforma onde se registam os serviços deste contrato
  -- (para comparar contratado com realizado). Opcional.
  sector TEXT CHECK (sector IN ('manutencoes', 'limpezas', 'abastecimentos', 'fumigacoes', 'incidentes')),
  notes TEXT,
  created_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX contracts_org_idx ON public.contracts (organization_id);

-- Parte do valor de cada prestação atribuída a um centro de custo.
CREATE TABLE public.contract_allocations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  contract_id UUID NOT NULL REFERENCES public.contracts(id) ON DELETE CASCADE,
  -- Centro de custo como aparece no plano de contas (ex.: "201 - Agência M Park").
  cost_center TEXT NOT NULL,
  -- Ligação à agência, quando o centro de custo é uma agência.
  agency_id UUID REFERENCES public.agencies(id) ON DELETE SET NULL,
  amount NUMERIC NOT NULL CHECK (amount >= 0),
  -- Como se chegou ao valor (ex.: "280 418,36 base + 4 261,53 área extra").
  notes TEXT,
  created_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX contract_allocations_contract_idx ON public.contract_allocations (contract_id);
CREATE INDEX contract_allocations_org_idx ON public.contract_allocations (organization_id);

CREATE OR REPLACE FUNCTION public.touch_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER contracts_touch BEFORE UPDATE ON public.contracts
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['contracts', 'contract_allocations'] LOOP
    EXECUTE format('CREATE TRIGGER %I BEFORE INSERT OR UPDATE ON public.%I
      FOR EACH ROW EXECUTE FUNCTION public.set_row_owner()', t || '_set_owner', t);
    EXECUTE format('CREATE TRIGGER %I BEFORE INSERT OR UPDATE ON public.%I
      FOR EACH ROW EXECUTE FUNCTION public.set_row_creator()', t || '_set_creator', t);
    EXECUTE format('CREATE TRIGGER %I AFTER INSERT OR UPDATE OR DELETE ON public.%I
      FOR EACH ROW EXECUTE FUNCTION public.audit_changes()', t || '_audit', t);
    EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON public.%I TO authenticated', t);
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('CREATE POLICY org_select ON public.%I FOR SELECT TO authenticated
      USING (organization_id = public.current_org_id() AND public.has_sector(''contratos''))', t);
    EXECUTE format('CREATE POLICY org_insert ON public.%I FOR INSERT TO authenticated
      WITH CHECK (organization_id = public.current_org_id() AND public.can_write(''contratos''))', t);
    EXECUTE format('CREATE POLICY org_update ON public.%I FOR UPDATE TO authenticated
      USING (organization_id = public.current_org_id() AND public.can_write(''contratos''))
      WITH CHECK (organization_id = public.current_org_id() AND public.can_write(''contratos''))', t);
    EXECUTE format('CREATE POLICY org_delete ON public.%I FOR DELETE TO authenticated
      USING (organization_id = public.current_org_id() AND public.can_delete(''contratos''))', t);
  END LOOP;
END $$;

-- O histórico dos contratos segue as permissões do setor Contratos.
CREATE OR REPLACE FUNCTION public.table_sector(tbl TEXT)
RETURNS TEXT LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN tbl IN ('maintenances', 'maintenance_labor', 'maintenance_materials',
                 'maintenance_documents', 'maintenance_schedules') THEN 'manutencoes'
    WHEN tbl IN ('cleanings', 'cleaning_schedules') THEN 'limpezas'
    WHEN tbl IN ('supplies', 'supply_schedules', 'fuel_readings') THEN 'abastecimentos'
    WHEN tbl = 'fumigations' THEN 'fumigacoes'
    WHEN tbl = 'incidents' THEN 'incidentes'
    WHEN tbl IN ('contracts', 'contract_allocations') THEN 'contratos'
  END;
$$;
