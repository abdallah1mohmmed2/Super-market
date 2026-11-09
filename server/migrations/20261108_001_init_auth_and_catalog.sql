BEGIN;
CREATE TABLE branches(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),name text NOT NULL,created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now(),deleted_at timestamptz);
CREATE TABLE roles(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),code text NOT NULL UNIQUE,name text NOT NULL,created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now(),deleted_at timestamptz);
CREATE TABLE role_permissions(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),role_id uuid NOT NULL REFERENCES roles(id),permission text NOT NULL,created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now(),deleted_at timestamptz,UNIQUE(role_id,permission));
CREATE TABLE users(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),firebase_uid text NOT NULL UNIQUE,display_name text NOT NULL,branch_id uuid NOT NULL REFERENCES branches(id),role_id uuid NOT NULL REFERENCES roles(id),is_active boolean NOT NULL DEFAULT true,created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now(),deleted_at timestamptz,UNIQUE(id,branch_id));
CREATE TABLE devices(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),user_id uuid NOT NULL REFERENCES users(id),fcm_token text NOT NULL UNIQUE,platform text NOT NULL CHECK(platform IN ('ANDROID','WINDOWS','WEB')),created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now(),deleted_at timestamptz);
CREATE TABLE idempotency_keys(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),user_id uuid NOT NULL,branch_id uuid NOT NULL,route text NOT NULL,operation_key uuid NOT NULL,payload_hash text NOT NULL,response jsonb NOT NULL,created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now(),deleted_at timestamptz,FOREIGN KEY(user_id,branch_id) REFERENCES users(id,branch_id),UNIQUE(user_id,branch_id,route,operation_key));
CREATE TABLE audit_logs(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),branch_id uuid NOT NULL REFERENCES branches(id),user_id uuid NOT NULL REFERENCES users(id),action text NOT NULL,entity_type text NOT NULL,entity_id uuid NOT NULL,old_values jsonb,new_values jsonb,event_at timestamptz NOT NULL DEFAULT now(),created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now(),deleted_at timestamptz);
CREATE TABLE product_categories(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),branch_id uuid NOT NULL REFERENCES branches(id),name text NOT NULL,created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now(),deleted_at timestamptz,UNIQUE(id,branch_id));
CREATE TABLE products(
 id uuid PRIMARY KEY,branch_id uuid NOT NULL REFERENCES branches(id),category_id uuid,code text NOT NULL,name text NOT NULL,base_unit text NOT NULL,is_weighted boolean NOT NULL DEFAULT false,
 scale_plu_code text CHECK(scale_plu_code IS NULL OR scale_plu_code ~ '^[0-9]{4}$'),
 stock_base_qty numeric(20,6) NOT NULL DEFAULT 0 CHECK(stock_base_qty>=0),avg_cost_base_unit numeric(20,6) NOT NULL DEFAULT 0 CHECK(avg_cost_base_unit>=0),revision integer NOT NULL DEFAULT 1 CHECK(revision>0),
 created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now(),deleted_at timestamptz,UNIQUE(id,branch_id),
 FOREIGN KEY(category_id,branch_id) REFERENCES product_categories(id,branch_id),CHECK(is_weighted OR scale_plu_code IS NULL),CHECK(length(trim(name)) BETWEEN 1 AND 160),CHECK(length(trim(code)) BETWEEN 1 AND 40));
CREATE UNIQUE INDEX products_code_active ON products(branch_id,code) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX products_plu_active ON products(branch_id,scale_plu_code) WHERE deleted_at IS NULL AND scale_plu_code IS NOT NULL;
CREATE INDEX products_branch_cursor ON products(branch_id,id) WHERE deleted_at IS NULL;
CREATE TABLE product_units_barcodes(
 id uuid PRIMARY KEY,product_id uuid NOT NULL,branch_id uuid NOT NULL,unit_name text NOT NULL CHECK(length(trim(unit_name)) BETWEEN 1 AND 30),conversion_factor numeric(18,6) NOT NULL CHECK(conversion_factor>0),barcode text CHECK(barcode IS NULL OR barcode ~ '^[0-9]{8,14}$'),retail_price numeric(18,2) NOT NULL DEFAULT 0 CHECK(retail_price>=0),wholesale_price numeric(18,2) NOT NULL DEFAULT 0 CHECK(wholesale_price>=0),cost_price numeric(18,2) NOT NULL DEFAULT 0 CHECK(cost_price>=0),created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now(),deleted_at timestamptz,
 FOREIGN KEY(product_id,branch_id) REFERENCES products(id,branch_id));
CREATE UNIQUE INDEX units_barcode_active ON product_units_barcodes(branch_id,barcode) WHERE deleted_at IS NULL AND barcode IS NOT NULL;
CREATE UNIQUE INDEX units_name_active ON product_units_barcodes(product_id,unit_name) WHERE deleted_at IS NULL;
CREATE INDEX units_product_active ON product_units_barcodes(product_id) WHERE deleted_at IS NULL;
CREATE FUNCTION touch_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN NEW.updated_at=clock_timestamp();RETURN NEW;END;$$;
DO $$ DECLARE t text;BEGIN FOREACH t IN ARRAY ARRAY['branches','roles','role_permissions','users','devices','products','product_units_barcodes','product_categories'] LOOP EXECUTE format('CREATE TRIGGER touch_updated_at BEFORE UPDATE ON %I FOR EACH ROW EXECUTE FUNCTION touch_updated_at()',t);END LOOP;END;$$;
INSERT INTO roles(code,name) VALUES('ADMIN','مدير النظام'),('MANAGER','مدير الفرع'),('CASHIER','الكاشير'),('ACCOUNTANT','المحاسب'),('WAREHOUSE','أمين المخزن'),('PURCHASER','المشتريات'),('VIEWER','المشاهدة');
INSERT INTO role_permissions(role_id,permission) SELECT r.id,p.permission FROM roles r CROSS JOIN (VALUES('catalog.read'),('catalog.write'),('reports.cost.view')) p(permission) WHERE r.code IN ('ADMIN','MANAGER');
INSERT INTO role_permissions(role_id,permission) SELECT id,'catalog.read' FROM roles WHERE code NOT IN ('ADMIN','MANAGER');
COMMIT;
