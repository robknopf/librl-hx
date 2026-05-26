import rl.RL;

class TestBindings {
    static function main() {
        trace("Testing librl-hx with existing working bindings...");
        
        // Use @:await syntax for async operations
        @await testAsync();
    }
    
    @async static function testAsync():Void {
        try {
            // Initialize librl
            var rc = @await RL.boot();
            trace('Boot result: $rc');
            if (rc == RL.BOOT_OK) {
                // Create window
                rc = @await RL.init({
                    windowTitle: "librl-hx Test"
                });
                trace('Init result: $rc');
                if (rc == RL.INIT_OK) {
                    trace("librl-hx working correctly!");
                    
                    // Test some basic operations
                    var platform = RL.getPlatform();
                    trace('Platform: $platform');
                    var version = RL.versionString();
                    trace('Version: $version');
                    
                    // Cleanup
                    @await RL.deinit();
                    trace("Test complete!");
                }
            }
        } catch (ex) {
            trace('Error: $ex');
        }
    }
}
