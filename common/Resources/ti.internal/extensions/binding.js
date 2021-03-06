/**
 * This file is used to hijack the standard require to allow for JS
 * implementations of "core" modules.
 *
 * You add a binding from the "core" module id to the under the hood JS
 * implementation. We then intercept require calls to handle requests for these modules
 * and lazily load the file.
 */

/**
 * Used by @function bindObjectToCoreModuleId
 * @type {map<string, object>}
 */
const bindings = new Map();

/**
 * Used by @function redirectCoreModuleIdToPath
 * @type {map<string, string>}
 */
const redirects = new Map();

/**
 * Does the request look like a typical core module? (no '.' or '/' characters)
 * @param {string} path original require path/id
 * @returns {boolean}
 */
function isCoreModuleId(path) {
	return !path.includes('.') && !path.includes('/');
}

// Hack require to point to this as a core module "binding"
const originalRequire = global.require;
// This works for iOS as-is, and also intercepts the call on Android for ti.main.js (the first file executed)
global.require = function (moduleId) {
	if (isCoreModuleId(moduleId)) {
		if (bindings.has(moduleId)) {
			return bindings.get(moduleId);
		}
		if (redirects.has(moduleId)) {
			moduleId = redirects.get(moduleId);
		}
	}
	return originalRequire(moduleId);
};

if (Ti.Platform.name === 'android') {
	// ... but we still need to hack it when requiring from other files for Android
	const originalModuleRequire = global.Module.prototype.require;
	global.Module.prototype.require = function (path, context) {
		if (isCoreModuleId(path)) {
			if (bindings.has(path)) {
				return bindings.get(path);
			}
			if (redirects.has(path)) {
				path = redirects.get(path);
			}
		}
		return originalModuleRequire.call(this, path, context);
	};
}

/**
 * Registers a binding from a short module id to the full under the hood filepath.
 * This allows for lazy instantiation of the module on-demand.
 *
 * @param {string} coreModuleId the module id to "hijack"
 * @param {string} internalPath the full filepath to require under the hood.
 *                              This should be an already resolved absolute path,
 *                              as otherwise the context of the call could change what gets loaded!
 */
export function redirectCoreModuleIdToPath(coreModuleId, internalPath) {
	redirects.set(coreModuleId, internalPath);
}

// TODO: Allow two types of bindings: a "redirect" from a "core" module id to the actual underlying file (as we have here)
// OR binding an object already loaded to a "core" module id

/**
 * Registers a binding from a short module id to already loaded/constructed object to export for that core module id.
 * @param {string} coreModuleId the core module id to register under
 * @param {object} object the object to hook to respond to require requests for the module id
 */
export function bindObjectToCoreModuleId(coreModuleId, object) {
	bindings.set(coreModuleId, object);
}
