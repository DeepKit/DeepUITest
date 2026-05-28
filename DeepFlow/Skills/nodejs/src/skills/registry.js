/**
 * Skill Registry - manages skill registration and lookup
 */

export class SkillRegistry {
  /**
   * @param {Object} logger Winston logger instance
   */
  constructor(logger) {
    this._skills = new Map();
    this._logger = logger;
  }

  /**
   * Register a skill
   * @param {BaseSkill} skill Skill instance to register
   */
  register(skill) {
    if (this._skills.has(skill.name)) {
      this._logger.warn(`Skill '${skill.name}' is being overwritten`);
    }
    
    this._skills.set(skill.name, skill);
    this._logger.debug(`Registered skill: ${skill.name} v${skill.version}`);
  }

  /**
   * Unregister a skill
   * @param {string} name Skill name
   */
  unregister(name) {
    if (this._skills.delete(name)) {
      this._logger.debug(`Unregistered skill: ${name}`);
    }
  }

  /**
   * Get a skill by name
   * @param {string} name Skill name
   * @returns {BaseSkill|undefined}
   */
  get(name) {
    return this._skills.get(name);
  }

  /**
   * Check if a skill exists
   * @param {string} name Skill name
   * @returns {boolean}
   */
  has(name) {
    return this._skills.has(name);
  }

  /**
   * Get count of registered skills
   * @returns {number}
   */
  count() {
    return this._skills.size;
  }

  /**
   * List all registered skills
   * @returns {Array<BaseSkill>}
   */
  listSkills() {
    return Array.from(this._skills.values());
  }

  /**
   * Get skill names
   * @returns {Array<string>}
   */
  getNames() {
    return Array.from(this._skills.keys());
  }

  /**
   * Clear all skills
   */
  clear() {
    this._skills.clear();
    this._logger.debug('Cleared all skills');
  }
}
