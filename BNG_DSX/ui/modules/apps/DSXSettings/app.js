/* global angular, bngApi */
angular.module("beamng.apps").directive("dsxSettings", [
    "$interval",
    "$timeout",
    function ($interval, $timeout) {
        "use strict";
        return {
            templateUrl: "/ui/modules/apps/DSXSettings/app.html",
            restrict: "EA",
            replace: true,
            scope: true,
            link: function (scope) {
                // BeamNG recreates HUD apps when leaving its menus; always start out of the way
                var vm = (scope.dsx = {
                    values: {},
                    saved: {},
                    defaults: {},
                    fields: [],
                    groups: [],
                    errors: {},
                    profileNames: [],
                    selectedProfile: "",
                    profileName: "",
                    profileBusy: false,
                    profilesOpen: false,
                    profileMessage: "",
                    profileError: "",
                    profileWarning: "",
                    profilePickerOpen: false,
                    deleteArmed: false,
                    status: {},
                    ready: false,
                    busy: false,
                    dirty: false,
                    collapsed: true,
                    message: "",
                    error: "",
                    statusStale: true,
                });
                var pending = null;
                var responseTimeout = null;
                var lastStatus = 0;
                var destroyed = false;
                var statusTimer = null;
                var profileTimeout = null;
                var pendingProfile = null;
                var profileRequestId = null;
                var profileSequence = 0;
                var profileClientId = Date.now().toString(36) + "-" + Math.random().toString(36).slice(2);

                function finishRequest() {
                    if (responseTimeout) $timeout.cancel(responseTimeout);
                    responseTimeout = null;
                    pending = null;
                    vm.busy = false;
                }

                function request(lua, action) {
                    if (action) {
                        finishRequest();
                        pending = action;
                        vm.busy = true;
                        vm.error = "";
                        vm.message = "";
                        responseTimeout = $timeout(function () {
                            finishRequest();
                            vm.error = "No settings response from BeamNG. Your draft is kept. Use Reload saved to retry.";
                        }, 5000);
                    }
                    try {
                        bngApi.engineLua(lua);
                    } catch (error) {
                        if (action) finishRequest();
                        vm.error = "Could not reach the DSX settings extension. Use Reload saved to retry.";
                    }
                }

                function fieldError(field) {
                    var value = vm.values[field.key];
                    if (field.kind === "boolean") return typeof value === "boolean" ? "" : "Choose on or off.";
                    if (field.kind === "number") {
                        if (typeof value !== "number" || !isFinite(value)) return "Enter a number.";
                        if (field.step === 1 && value % 1 !== 0) return "Enter a whole number.";
                        if (field.min != null && value < field.min) return "Minimum: " + field.min;
                        if (field.max != null && value > field.max) return "Maximum: " + field.max;
                    } else if (field.kind === "color") {
                        if (typeof value !== "string" || !/^#[0-9a-f]{6}$/i.test(value)) return "Use a six-digit color, for example #FFC800.";
                    } else if (typeof value !== "string" || !value.trim()) {
                        return "This field is required.";
                    }
                    return "";
                }

                function updateDirty() {
                    vm.dirty = !angular.equals(vm.values, vm.saved);
                }

                vm.changed = function (field) {
                    delete vm.errors[field.key];
                    var error = fieldError(field);
                    if (error) vm.errors[field.key] = error;
                    vm.message = "";
                    updateDirty();
                };

                function validatedForm() {
                    vm.errors = {};
                    // Only schema keys are sent, and BeamNG's serializer escapes user-entered text
                    var values = {};
                    vm.fields.forEach(function (field) {
                        var error = fieldError(field);
                        if (error) vm.errors[field.key] = error;
                        values[field.key] = vm.values[field.key];
                    });
                    if (Object.keys(vm.errors).length) {
                        vm.error = "Fix the marked fields before saving.";
                        vm.groups.forEach(function (group) {
                            if (
                                group.fields.some(function (field) {
                                    return vm.errors[field.key];
                                })
                            )
                                group.open = true;
                        });
                        return;
                    }
                    return values;
                }

                vm.apply = function () {
                    if (!vm.ready || vm.busy || vm.profileBusy) return;
                    var values = validatedForm();
                    if (values) request("extensions.dsxSettings.apply(" + bngApi.serializeToLua(values) + ")", "save");
                };

                vm.reset = function () {
                    if (!vm.ready || vm.busy || vm.profileBusy) return;
                    vm.values = angular.copy(vm.defaults);
                    vm.errors = {};
                    vm.error = "";
                    vm.message = "Defaults are in the form. Apply & Save to keep them.";
                    updateDirty();
                };

                vm.reload = function () {
                    if (vm.busy || vm.profileBusy) return;
                    request("extensions.load('dsxSettings'); extensions.dsxSettings.requestState()", "load");
                };

                vm.reconnect = function () {
                    if (vm.busy || vm.profileBusy) return;
                    vm.message = "Reconnect requested for the current saved settings.";
                    request("extensions.dsxSettings.reconnect()");
                };

                function finishProfileRequest() {
                    if (profileTimeout) $timeout.cancel(profileTimeout);
                    profileTimeout = null;
                    pendingProfile = null;
                    profileRequestId = null;
                    vm.profileBusy = false;
                }

                function setProfileNames(names, warning) {
                    vm.profileNames = Array.isArray(names) ? names : [];
                    vm.profileWarning = warning || "";
                    if (vm.profileNames.indexOf(vm.selectedProfile) < 0) vm.selectedProfile = "";
                    if (!vm.profileNames.length) vm.profilePickerOpen = false;
                }

                function profileRequest(method, args, action) {
                    if (vm.busy || vm.profileBusy || destroyed) return;
                    vm.profileBusy = true;
                    vm.profilePickerOpen = false;
                    pendingProfile = action;
                    profileRequestId = profileClientId + "-" + ++profileSequence;
                    vm.profileError = "";
                    vm.profileMessage = "";
                    vm.deleteArmed = false;
                    profileTimeout = $timeout(function () {
                        finishProfileRequest();
                        vm.profileError = "No profile response. Your form is kept; reload saved settings to refresh the list.";
                    }, 5000);
                    try {
                        // Names and settings are data: always use BeamNG's serializer for every argument
                        var argumentsLua = args
                            .concat([profileRequestId])
                            .map(function (value) {
                                return bngApi.serializeToLua(value);
                            })
                            .join(",");
                        bngApi.engineLua("extensions.dsxSettings." + method + "(" + argumentsLua + ")");
                    } catch (error) {
                        finishProfileRequest();
                        vm.profileError = "Could not reach profiles. Reload saved settings to retry.";
                    }
                }

                // Use ordinary in-panel buttons; the game may not display a native select popup
                vm.selectProfile = function (name) {
                    if (!vm.ready || vm.busy || vm.profileBusy || vm.profileNames.indexOf(name) < 0) return;
                    vm.selectedProfile = name;
                    vm.profileName = name;
                    vm.profilePickerOpen = false;
                    vm.profileMessage = "";
                    vm.profileError = "";
                    vm.deleteArmed = false;
                };

                vm.saveProfile = function (overwrite) {
                    if (!vm.ready || vm.busy || vm.profileBusy) return;
                    var name = overwrite ? vm.selectedProfile : (vm.profileName || "").trim();
                    if (!name) {
                        vm.profileError = "Enter a profile name or select a profile to update.";
                        return;
                    }
                    var values = validatedForm();
                    if (!values) {
                        vm.profileError = "Fix the marked settings before saving a profile.";
                        return;
                    }
                    profileRequest("saveProfile", [name, values, !!overwrite], "save");
                };

                vm.loadProfile = function () {
                    if (vm.selectedProfile) profileRequest("loadProfile", [vm.selectedProfile], "load");
                };

                vm.renameProfile = function () {
                    var name = (vm.profileName || "").trim();
                    if (!name) {
                        vm.profileError = "Enter the new name.";
                        return;
                    }
                    if (vm.selectedProfile) profileRequest("renameProfile", [vm.selectedProfile, name], "rename");
                };

                vm.deleteProfile = function () {
                    if (!vm.selectedProfile || vm.busy || vm.profileBusy) return;
                    if (!vm.deleteArmed) {
                        vm.deleteArmed = true;
                        return;
                    }
                    profileRequest("deleteProfile", [vm.selectedProfile], "delete");
                };

                scope.$on("DSXProfileResult", function (event, result) {
                    if (destroyed || !result) return;
                    scope.$evalAsync(function () {
                        if (destroyed) return;
                        setProfileNames(result.names, result.profileWarning);
                        // An unrelated or late reply may refresh the list, but must not replace a draft
                        if (result.action !== pendingProfile || result.requestId !== profileRequestId) return;
                        finishProfileRequest();
                        var errors = result.errors || {};
                        vm.profileMessage = result.message || "";
                        if (!result.ok) {
                            vm.profileError = errors._name || errors._general || result.message || "Profile operation failed.";
                            // Only saving this form can attach validation errors to its fields
                            if (result.action === "save") {
                                vm.fields.forEach(function (field) {
                                    if (errors[field.key]) vm.errors[field.key] = errors[field.key];
                                });
                                vm.groups.forEach(function (group) {
                                    if (
                                        group.fields.some(function (field) {
                                            return vm.errors[field.key];
                                        })
                                    )
                                        group.open = true;
                                });
                            }
                            return;
                        }
                        vm.profileError = "";
                        if (result.action === "delete") {
                            vm.selectedProfile = "";
                            vm.profileName = "";
                        } else {
                            vm.selectedProfile = result.name || vm.selectedProfile;
                            vm.profileName = vm.selectedProfile;
                        }
                        if (result.action === "load" && result.values) {
                            vm.values = angular.copy(result.values);
                            vm.errors = {};
                            vm.error = "";
                            vm.message = "Profile loaded into the form. Apply & Save to activate it.";
                            updateDirty();
                        }
                    });
                });

                scope.$on("DSXSettingsState", function (event, state) {
                    if (destroyed || !state || !state.values || !Array.isArray(state.fields)) return;
                    scope.$evalAsync(function () {
                        if (destroyed) return;
                        var action = pending;
                        finishRequest();
                        var errors = state.errors || {};
                        var hasErrors = Object.keys(errors).length > 0;
                        // Status uses a separate event. Unsolicited settings updates must not erase edits
                        if (!vm.ready || action === "load" || (action === "save" && !hasErrors) || !vm.dirty) {
                            vm.values = angular.copy(state.values);
                        }
                        setProfileNames(state.profileNames, state.profileWarning);
                        vm.saved = angular.copy(state.values);
                        vm.defaults = angular.copy(state.defaults || {});
                        vm.fields = state.fields;
                        var previousGroups = vm.groups;
                        vm.groups = [];
                        vm.fields.forEach(function (field) {
                            var name = field.group || "Other";
                            var group = vm.groups.filter(function (item) {
                                return item.name === name;
                            })[0];
                            if (!group) {
                                var previous = previousGroups.filter(function (item) {
                                    return item.name === name;
                                })[0];
                                group = {name: name, fields: [], open: previous ? previous.open : vm.groups.length === 0};
                                vm.groups.push(group);
                            }
                            group.fields.push(field);
                            if (errors[field.key]) group.open = true;
                        });
                        vm.errors = errors;
                        vm.ready = true;
                        vm.error = hasErrors ? "Settings were not saved. Fix the marked fields." : "";
                        vm.message = state.message || "";
                        updateDirty();
                    });
                });

                scope.$on("DSXSettingsStatus", function (event, status) {
                    if (destroyed || !status) return;
                    scope.$evalAsync(function () {
                        if (destroyed) return;
                        vm.status = status;
                        vm.statusStale = false;
                        lastStatus = Date.now();
                    });
                });

                function pollStatus() {
                    if (vm.collapsed || destroyed) return;
                    vm.statusStale = !lastStatus || Date.now() - lastStatus > 5000;
                    request("if extensions.dsxSettings then extensions.dsxSettings.requestStatus() end");
                }

                function stopStatusPolling() {
                    if (statusTimer) $interval.cancel(statusTimer);
                    statusTimer = null;
                }

                function startStatusPolling() {
                    if (!statusTimer && !destroyed && !vm.collapsed) statusTimer = $interval(pollStatus, 1000);
                }

                vm.toggleCollapsed = function () {
                    if (destroyed) return;
                    vm.collapsed = !vm.collapsed;
                    if (vm.collapsed) {
                        stopStatusPolling();
                    } else {
                        // Refresh telemetry without reloading settings or replacing an unsaved draft
                        pollStatus();
                        startStatusPolling();
                    }
                };

                // No status requests while the panel is collapsed; effects continue in vehicle Lua
                startStatusPolling();

                scope.$on("$destroy", function () {
                    destroyed = true;
                    stopStatusPolling();
                    finishProfileRequest();
                    finishRequest();
                });
                vm.reload();
            },
        };
    },
]);
