"""Validate the OpenAPI document and real responses exported by Dart tests."""
import json
from pathlib import Path
from openapi_spec_validator import validate_spec
from openapi_schema_validator import OAS30Validator

root = Path(__file__).resolve().parents[1]
spec = json.loads((root / 'docs/openapi_v1.yaml').read_text())
validate_spec(spec)
samples_path = root / 'server/build/contract_samples.json'
if not samples_path.exists():
    raise SystemExit('Run server tests first; actual response samples are missing.')
samples = json.loads(samples_path.read_text())
def resolve_local(schema):
    """Resolve only local schema references; no remote downloads are necessary."""
    if isinstance(schema, list):
        return [resolve_local(item) for item in schema]
    if not isinstance(schema, dict):
        return schema
    if '$ref' in schema:
        pointer = schema['$ref']
        if not pointer.startswith('#/components/schemas/'):
            raise ValueError(f'Unsupported external reference: {pointer}')
        return resolve_local(spec['components']['schemas'][pointer.rsplit('/', 1)[1]])
    return {key: resolve_local(value) for key, value in schema.items()}

for sample in samples:
    operation = spec['paths'][sample['path']][sample['method'].lower()]
    response = operation['responses'][str(sample['status'])]
    if sample['status'] == 304:
        assert sample['body'] == '', '304 must not include a body'
        continue
    schema = response['content']['application/json']['schema']
    OAS30Validator(resolve_local(schema), format_checker=OAS30Validator.FORMAT_CHECKER).validate(sample['body'])
print(f'OpenAPI 3.0 valid; {len(samples)} actual HTTP responses match their schemas.')
