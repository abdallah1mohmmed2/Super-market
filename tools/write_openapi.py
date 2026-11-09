"""Generate the complete iteration-one OpenAPI 3.0 contract deterministically."""
from pathlib import Path
import json


def ref(name):
    """Reference a reusable schema."""
    return {'$ref': '#/components/schemas/' + name}


def obj(properties, required=None):
    """Require explicit fields and reject misspelled names."""
    result = {'type': 'object', 'additionalProperties': False, 'properties': properties}
    fields = list(properties) if required is None else required
    if fields:
        result['required'] = fields
    return result


text = {'type': 'string'}
uuid = {'type': 'string', 'format': 'uuid'}
money = {'type': 'string', 'pattern': r'^(0|[1-9][0-9]{0,12})\.[0-9]{2}$', 'example': '150.00'}
schemas = {}
schemas['PageMeta'] = obj({'page': {'type': 'integer', 'minimum': 1}, 'limit': {'type': 'integer', 'minimum': 1, 'maximum': 30}, 'nextCursor': {'type': 'string', 'nullable': True}, 'requestId': text})
schemas['ApiError'] = obj({'error': obj({'code': text, 'message': text, 'requestId': text})})
schemas['ProductUnitBarcodeDto'] = obj({'id': uuid, 'unitName': {'type': 'string', 'minLength': 1, 'maxLength': 30}, 'conversionFactor': {'type': 'number', 'exclusiveMinimum': True, 'minimum': 0, 'maximum': 1000000}, 'barcode': {'type': 'string', 'nullable': True, 'pattern': r'^\d{8,14}$'}, 'retailPrice': money, 'wholesalePrice': money, 'costPrice': money})
schemas['ProductDto'] = obj({'id': uuid, 'branchId': uuid, 'code': {'type': 'string', 'minLength': 1, 'maxLength': 40}, 'name': {'type': 'string', 'minLength': 1, 'maxLength': 160}, 'baseUnit': {'type': 'string', 'minLength': 1, 'maxLength': 30}, 'isWeighted': {'type': 'boolean'}, 'scalePluCode': {'type': 'string', 'nullable': True, 'pattern': r'^\d{4}$'}, 'categoryId': {**uuid, 'nullable': True}, 'units': {'type': 'array', 'minItems': 1, 'maxItems': 30, 'items': ref('ProductUnitBarcodeDto')}, 'stockBaseQty': {'type': 'number', 'minimum': 0, 'description': 'Server-owned. Creation always returns zero; definition edits preserve the authoritative quantity.'}, 'revision': {'type': 'integer', 'minimum': 0, 'description': 'Expected server revision. Zero creates; stale revisions return 409.'}, 'updatedAt': {'type': 'string', 'format': 'date-time', 'nullable': True}})
schemas['UserSessionDto'] = obj({'userId': uuid, 'firebaseUid': text, 'displayName': text, 'branchId': uuid, 'branchName': text, 'role': text, 'permissions': {'type': 'array', 'items': text}})
schemas['AppConfigDto'] = obj({'minimumVersion': text, 'latestVersion': text, 'country': text, 'supermarketName': text, 'featureFlags': {'type': 'object', 'additionalProperties': {'type': 'boolean'}}})
schemas['Health'] = obj({'status': {'type': 'string', 'enum': ['ok']}, 'version': text})
for name, data in [('ProductResponse', ref('ProductDto')), ('ProductsResponse', {'type': 'array', 'maxItems': 30, 'items': ref('ProductDto')}), ('SessionResponse', ref('UserSessionDto')), ('ConfigResponse', ref('AppConfigDto')), ('HealthResponse', ref('Health')), ('LookupResponse', {**schemas['ProductDto'], 'nullable': True})]:
    schemas[name] = obj({'data': data, 'meta': ref('PageMeta')})

request_id = {'name': 'X-Request-Id', 'in': 'header', 'required': True, 'schema': {'type': 'string', 'pattern': r'^[A-Za-z0-9._:-]{1,100}$'}}
key = {'name': 'Idempotency-Key', 'in': 'header', 'required': True, 'schema': {'type': 'string', 'format': 'uuid', 'description': 'Version-four UUID, persisted by the client and reused for retries.'}}
error = {'description': 'Uniform request-correlated failure', 'content': {'application/json': {'schema': ref('ApiError')}}}


def operation(operation_id, response, *, public=False, body=None, query=None, etag=False):
    """Construct a complete operation with security, headers, body and errors."""
    headers = {'X-Request-Id': {'schema': text, 'description': 'Correlation ID'}}
    if etag:
        headers['ETag'] = {'schema': text, 'description': 'Representation validator excluding request ID'}
    result = {'operationId': operation_id, 'security': [] if public else [{'FirebaseBearer': []}], 'parameters': [{**request_id, 'required': not public}] + (query or []), 'responses': {'200': {'description': 'Success', 'headers': headers, 'content': {'application/json': {'schema': ref(response)}}}, **{str(code): error for code in [400, 401, 403, 404, 409, 413, 429, 500, 503]}}}
    if body is not None:
        result['parameters'].append(key)
        result['requestBody'] = {'required': True, 'content': {'application/json': {'schema': body}}}
    if etag:
        result['parameters'].append({'name': 'If-None-Match', 'in': 'header', 'schema': text})
        result['responses']['304'] = {'description': 'Unchanged representation; empty body', 'headers': headers}
    return result


def query(name, schema):
    """Define an optional query argument."""
    return {'name': name, 'in': 'query', 'schema': schema}


spec = {'openapi': '3.0.3', 'info': {'title': 'Supermarket ERP — Iteration 01', 'version': '0.1.0', 'description': 'PostgreSQL is authoritative. All catalog reads and writes are restricted to the provisioned session branch. Money is an exact decimal string. Session POST is side-effect-free and always returns current permissions; product POST is transactionally idempotent.'}, 'servers': [{'url': '/'}], 'paths': {
    '/health': {'get': operation('health', 'HealthResponse', public=True)},
    '/v1/app-config': {'get': operation('appConfig', 'ConfigResponse', public=True)},
    '/v1/auth/session': {'post': operation('createSession', 'SessionResponse', body=obj({}))},
    '/v1/catalog/products': {'get': operation('listProducts', 'ProductsResponse', query=[query('cursor', text), query('q', {'type': 'string', 'maxLength': 160}), query('limit', {'type': 'integer', 'minimum': 1, 'default': 30, 'description': 'Values greater than thirty are clamped to thirty.'})], etag=True), 'post': operation('upsertProduct', 'ProductResponse', body=ref('ProductDto'))},
    '/v1/catalog/lookup': {'get': operation('lookupBarcodeOrPlu', 'LookupResponse', query=[{'name': 'code', 'in': 'query', 'required': True, 'schema': {'type': 'string', 'pattern': r'^(\d{4}|\d{8,14})$'}}])}},
    'components': {'securitySchemes': {'FirebaseBearer': {'type': 'http', 'scheme': 'bearer', 'bearerFormat': 'Firebase ID token (RS256)'}}, 'schemas': schemas}}
# JSON syntax is a valid YAML 1.2 document and preserves exact OpenAPI types.
Path('docs/openapi_v1.yaml').write_text(json.dumps(spec, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
