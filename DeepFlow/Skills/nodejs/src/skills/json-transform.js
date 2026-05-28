/**
 * JSON Transform Skill
 * 
 * Transforms JSON data using JSONPath expressions and mapping rules.
 */

import { z } from 'zod';
import { BaseSkill, SkillError } from './base.js';

const inputSchema = z.object({
  data: z.any().describe('Input JSON data to transform'),
  operations: z.array(z.object({
    type: z.enum(['extract', 'rename', 'delete', 'set', 'map', 'filter', 'flatten', 'merge']),
    path: z.string().optional(),
    source: z.string().optional(),
    target: z.string().optional(),
    value: z.any().optional(),
    expression: z.string().optional(),
    condition: z.string().optional()
  })).describe('List of transform operations')
});

const outputSchema = z.object({
  result: z.any(),
  operations_applied: z.number()
});

export class JsonTransformSkill extends BaseSkill {
  constructor() {
    super({
      name: 'json_transform',
      description: 'Transform JSON data using operations like extract, rename, map, filter',
      version: '1.0.0',
      inputSchema,
      outputSchema,
      examples: [
        {
          description: 'Extract and rename fields',
          input: {
            data: { user: { name: 'John', age: 30 } },
            operations: [
              { type: 'extract', path: 'user' },
              { type: 'rename', source: 'name', target: 'fullName' }
            ]
          },
          output: { result: { fullName: 'John', age: 30 }, operations_applied: 2 }
        }
      ]
    });
  }

  async execute(input, context) {
    let result = JSON.parse(JSON.stringify(input.data)); // Deep clone
    let operationsApplied = 0;

    for (const op of input.operations) {
      try {
        result = this._applyOperation(result, op);
        operationsApplied++;
      } catch (error) {
        throw new SkillError(
          'TRANSFORM_ERROR',
          `Failed to apply operation '${op.type}': ${error.message}`
        );
      }
    }

    return {
      result,
      operations_applied: operationsApplied
    };
  }

  _applyOperation(data, op) {
    switch (op.type) {
      case 'extract':
        return this._extract(data, op.path);

      case 'rename':
        return this._rename(data, op.source, op.target);

      case 'delete':
        return this._delete(data, op.path);

      case 'set':
        return this._set(data, op.path, op.value);

      case 'map':
        return this._map(data, op.path, op.expression);

      case 'filter':
        return this._filter(data, op.path, op.condition);

      case 'flatten':
        return this._flatten(data, op.path);

      case 'merge':
        return this._merge(data, op.value);

      default:
        throw new Error(`Unknown operation type: ${op.type}`);
    }
  }

  _extract(data, path) {
    const parts = path.split('.');
    let result = data;
    
    for (const part of parts) {
      if (result === null || result === undefined) return null;
      
      // Handle array index
      const match = part.match(/^(\w+)\[(\d+)\]$/);
      if (match) {
        result = result[match[1]];
        if (Array.isArray(result)) {
          result = result[parseInt(match[2])];
        }
      } else {
        result = result[part];
      }
    }
    
    return result;
  }

  _rename(data, source, target) {
    if (typeof data !== 'object' || data === null) return data;
    
    const result = { ...data };
    if (source in result) {
      result[target] = result[source];
      delete result[source];
    }
    
    return result;
  }

  _delete(data, path) {
    if (typeof data !== 'object' || data === null) return data;
    
    const result = { ...data };
    const parts = path.split('.');
    
    if (parts.length === 1) {
      delete result[path];
    } else {
      // Nested delete
      let current = result;
      for (let i = 0; i < parts.length - 1; i++) {
        if (current[parts[i]] === undefined) return result;
        current[parts[i]] = { ...current[parts[i]] };
        current = current[parts[i]];
      }
      delete current[parts[parts.length - 1]];
    }
    
    return result;
  }

  _set(data, path, value) {
    if (typeof data !== 'object' || data === null) {
      data = {};
    }
    
    const result = { ...data };
    const parts = path.split('.');
    
    if (parts.length === 1) {
      result[path] = value;
    } else {
      let current = result;
      for (let i = 0; i < parts.length - 1; i++) {
        if (current[parts[i]] === undefined) {
          current[parts[i]] = {};
        } else {
          current[parts[i]] = { ...current[parts[i]] };
        }
        current = current[parts[i]];
      }
      current[parts[parts.length - 1]] = value;
    }
    
    return result;
  }

  _map(data, path, expression) {
    const array = path ? this._extract(data, path) : data;
    
    if (!Array.isArray(array)) {
      throw new Error('Map operation requires an array');
    }
    
    // SECURITY: Validate expression before evaluation
    this._validateExpression(expression);
    
    // Simple expression evaluation (x => x.field or x => x * 2)
    const fn = new Function('x', `"use strict"; return ${expression}`);
    return array.map(fn);
  }

  _filter(data, path, condition) {
    const array = path ? this._extract(data, path) : data;
    
    if (!Array.isArray(array)) {
      throw new Error('Filter operation requires an array');
    }
    
    // SECURITY: Validate condition before evaluation
    this._validateExpression(condition);
    
    const fn = new Function('x', `"use strict"; return ${condition}`);
    return array.filter(fn);
  }
  
  /**
   * SECURITY: Validate expression to prevent code injection
   * @private
   */
  _validateExpression(expr) {
    if (!expr || typeof expr !== 'string') {
      throw new SkillError('INVALID_EXPRESSION', 'Expression must be a non-empty string');
    }
    
    // Dangerous patterns that could lead to code injection
    const dangerousPatterns = [
      /\beval\s*\(/i,
      /\bFunction\s*\(/i,
      /\bimport\s*\(/i,
      /\brequire\s*\(/i,
      /\bprocess\b/i,
      /\bglobal\b/i,
      /\bwindow\b/i,
      /\bdocument\b/i,
      /\b__proto__\b/,
      /\bconstructor\b/,
      /\bprototype\b/,
      /\bthis\b/,
      /\bfetch\s*\(/i,
      /\bXMLHttpRequest\b/i,
      /\bsetTimeout\s*\(/i,
      /\bsetInterval\s*\(/i,
    ];
    
    for (const pattern of dangerousPatterns) {
      if (pattern.test(expr)) {
        throw new SkillError(
          'UNSAFE_EXPRESSION',
          `Expression contains potentially dangerous code: ${expr.substring(0, 50)}`
        );
      }
    }
  }

  _flatten(data, path) {
    const array = path ? this._extract(data, path) : data;
    
    if (!Array.isArray(array)) {
      throw new Error('Flatten operation requires an array');
    }
    
    return array.flat();
  }

  _merge(data, value) {
    if (typeof data !== 'object' || typeof value !== 'object') {
      throw new Error('Merge operation requires objects');
    }
    
    return { ...data, ...value };
  }
}
