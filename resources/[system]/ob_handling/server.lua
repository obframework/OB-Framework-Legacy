OR.Callback.register('access', function(src)
    return exports.ob_admin:HasPermission(src, HandlingEditor.Permission) == true
end)
