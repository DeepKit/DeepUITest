/**
 * @deepspec/reader - Minimal DeepSpec Protocol Reader (Level 1, v1.2-draft aware)
 *
 * Reads .deepspec/ directories and provides typed access to
 * project facts, trees, and decisions.
 */

import { readFileSync, existsSync } from 'fs';
import { join } from 'path';
import { parse as parseYaml } from 'yaml';

// --- Types ---

export type TreeType = 'function' | 'module' | 'view' | 'data';
export type NodeStatus = 'candidate' | 'confirmed' | 'uncertain' | 'rejected' | 'superseded';
export type Confidence = 'low' | 'medium' | 'high';
export type SourceLayer = 'parsed_from_a' | 'human_decision' | 'ai_inferred' | 'generated_summary';

export interface SourceRef {
  ref_id: string;
  relevance?: 'primary' | 'supporting' | 'contradicting' | null;
  note?: string | null;
}

export interface TreeNode {
  id: string;
  tree: TreeType;
  title: string;
  kind: string;
  parent_id?: string | null;
  slug_override?: string | null;
  summary?: string;
  status: NodeStatus;
  confidence: Confidence;
  source_layer: SourceLayer;
  source_refs: SourceRef[];
  decision_refs: string[];
  issue_refs: string[];
  related_functions: string[];
  related_modules: string[];
  related_views: string[];
  children: string[];
  tags: string[];
  acceptance_criteria: string[];
  not_doing: string[];
  created_at?: string;
  updated_at?: string;
  content_hash?: string;
  relation_hash?: string;
  revision: number;
}

export interface TreeFile {
  version: string;
  tree: TreeType;
  generated_at: string;
  generator: string;
  nodes: TreeNode[];
}

export interface ProjectSpec {
  version: string;
  project: {
    name: string;
    path: string;
    type: string;
    scan_time: string;
  };
  summary: {
    total_nodes: number;
    confirmed_nodes: number;
    uncertain_nodes: number;
    open_issues: number;
    decisions_count: number;
  };
  trees: {
    function_tree: string;
    module_tree: string;
    view_tree: string;
    data_tree?: string;
  };
}

export interface Decision {
  id: string;
  type: string;
  title: string;
  decision: string;
  rationale: string;
  target_nodes: string[];
  ai_instruction?: string | null;
  status: string;
  decided_by: 'human' | 'system';
}

// --- Defaults ---

const NODE_DEFAULTS: Partial<TreeNode> = {
  status: 'candidate',
  confidence: 'medium',
  source_layer: 'ai_inferred',
  source_refs: [],
  decision_refs: [],
  issue_refs: [],
  related_functions: [],
  related_modules: [],
  related_views: [],
  children: [],
  tags: [],
  acceptance_criteria: [],
  not_doing: [],
  revision: 1,
};

// --- Reader ---

export class DeepSpecReader {
  private basePath: string;
  private _project: ProjectSpec | null = null;
  private _trees: Map<TreeType, TreeFile> = new Map();

  constructor(projectRoot: string) {
    this.basePath = join(projectRoot, '.deepspec');
  }

  /** Check if this project has a .deepspec directory */
  exists(): boolean {
    return existsSync(join(this.basePath, 'project-spec.yaml'));
  }

  /** Load and return the project specification */
  project(): ProjectSpec {
    if (!this._project) {
      const raw = this.readYaml('project-spec.yaml');
      this._project = raw as ProjectSpec;
    }
    return this._project;
  }

  /** Load a specific tree */
  tree(type: TreeType): TreeFile {
    if (!this._trees.has(type)) {
      const proj = this.project();
      const path = proj.trees[`${type}_tree` as keyof typeof proj.trees];
      const raw = this.readYaml(path);
      const file = raw as TreeFile;
      // Apply defaults to nodes
      file.nodes = file.nodes.map(node => ({ ...NODE_DEFAULTS, ...node }) as TreeNode);
      this._trees.set(type, file);
    }
    return this._trees.get(type)!;
  }

  /** Get all nodes across all trees */
  allNodes(): TreeNode[] {
    const types: TreeType[] = ['function', 'module', 'view', 'data'];
    return types.flatMap(t => {
      try {
        return this.tree(t).nodes;
      } catch {
        return [];
      }
    });
  }

  /** Find a node by ID */
  findNode(id: string): TreeNode | undefined {
    return this.allNodes().find(n => n.id === id);
  }

  /** Get root nodes (no parent) for a tree */
  roots(type: TreeType): TreeNode[] {
    return this.tree(type).nodes.filter(n => !n.parent_id);
  }

  /** Get children of a node */
  childrenOf(parentId: string): TreeNode[] {
    return this.allNodes().filter(n => n.parent_id === parentId);
  }

  /** Load accepted decisions */
  decisions(): Decision[] {
    try {
      const raw = this.readYaml('decisions/requirement-decisions.yaml') as any;
      return (raw.decisions || []) as Decision[];
    } catch {
      return [];
    }
  }

  /** Get accepted decisions only */
  acceptedDecisions(): Decision[] {
    return this.decisions().filter(d => d.status === 'accepted');
  }

  /** Get AI instructions from accepted decisions */
  aiInstructions(): string[] {
    return this.acceptedDecisions()
      .filter(d => d.ai_instruction)
      .map(d => d.ai_instruction!);
  }

  private readYaml(relativePath: string): unknown {
    const fullPath = join(this.basePath, relativePath);
    if (!existsSync(fullPath)) {
      throw new Error(`DeepSpec file not found: ${relativePath}`);
    }
    const content = readFileSync(fullPath, 'utf-8');
    return parseYaml(content);
  }
}

// --- Convenience ---

export function openDeepSpec(projectRoot: string): DeepSpecReader | null {
  const reader = new DeepSpecReader(projectRoot);
  return reader.exists() ? reader : null;
}
