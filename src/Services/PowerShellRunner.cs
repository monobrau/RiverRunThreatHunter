using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Threading.Tasks;
using Newtonsoft.Json;

namespace RiverRunThreatHunter.Services
{
    public class PowerShellRunner
    {
        private readonly string _modulePath;
        private static readonly string _debugLogPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "RiverRunThreatHunter_Debug.log");
        
        public PowerShellRunner(string modulePath)
        {
            _modulePath = modulePath;
        }
        
        public string ModulePath => _modulePath;
        
        public static void WriteDebugLog(string message)
        {
            try
            {
                var timestamp = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss.fff");
                // Ensure directory exists
                var dir = Path.GetDirectoryName(_debugLogPath);
                if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir))
                {
                    Directory.CreateDirectory(dir);
                }
                File.AppendAllText(_debugLogPath, $"[{timestamp}] {message}\n");
                Debug.WriteLine(message);
            }
            catch (Exception ex)
            {
                // Log to debug output even if file write fails
                Debug.WriteLine($"Failed to write debug log: {ex.Message}");
                Debug.WriteLine($"Debug log path: {_debugLogPath}");
            }
        }
        
        public static string DebugLogPath => _debugLogPath;
        
        /// <summary>
        /// Filters out non-critical Diagnostics.dll errors that are common with PowerShell modules
        /// </summary>
        private static List<ErrorRecord> FilterDiagnosticsErrors(ICollection<ErrorRecord> errors)
        {
            return errors.Where(e =>
            {
                var err = e.ToString().ToLowerInvariant();
                var exceptionMsg = e.Exception?.Message?.ToLowerInvariant() ?? "";
                var errorId = e.FullyQualifiedErrorId?.ToLowerInvariant() ?? "";
                
                // Filter out Microsoft.PowerShell.Commands.Diagnostics.dll snap-in errors (non-critical)
                // These are common warnings when PowerShell modules are imported
                var isDiagnosticsError = err.Contains("microsoft.powershell.commands.diagnostics") ||
                                        err.Contains("diagnostics.dll") ||
                                        err.Contains("cannot load powershell snap-in") ||
                                        err.Contains("snap-in") ||
                                        err.Contains("snapin") ||
                                        exceptionMsg.Contains("diagnostics") ||
                                        errorId.Contains("diagnostics");
                
                return !isDiagnosticsError;
            }).ToList();
        }
        
        /// <summary>
        /// Checks if an exception message contains Diagnostics.dll errors (non-critical)
        /// </summary>
        public static bool IsDiagnosticsError(string errorMessage)
        {
            if (string.IsNullOrEmpty(errorMessage)) return false;
            
            var err = errorMessage.ToLowerInvariant();
            // Check for various Diagnostics.dll error patterns
            return err.Contains("microsoft.powershell.commands.diagnostics") ||
                   err.Contains("diagnostics.dll") ||
                   err.Contains("diagnostics") && (err.Contains("snap") || err.Contains("snap-in") || err.Contains("cannot load")) ||
                   err.Contains("cannot load powershell snap-in") ||
                   err.Contains("powershell snap-in") && err.Contains("diagnostics") ||
                   err.Contains("module") && err.Contains("diagnostics") && err.Contains("load");
        }
        
        public PowerShellRunner()
        {
            // Get module path relative to executable location
            var exeDir = AppDomain.CurrentDomain.BaseDirectory;
            
            // Try multiple paths:
            // 1. Relative to exe (for deployed app): ..\..\modules
            // Try 4 levels up first (net8.0-windows -> Debug -> bin -> src -> project root)
            var projectRoot1 = Path.GetFullPath(Path.Combine(exeDir, "..", "..", "..", ".."));
            // Also try 3 levels up (fallback)
            var projectRoot1Alt = Path.GetFullPath(Path.Combine(exeDir, "..", "..", ".."));
            var modulePath1 = Path.Combine(projectRoot1, "modules");
            
            // 2. Same directory as exe
            var modulePath2 = Path.Combine(exeDir, "modules");
            
            // 3. Current working directory (for development)
            var modulePath3 = Path.Combine(Directory.GetCurrentDirectory(), "modules");
            
            // 4. Parent of exe directory
            var parentDir = Path.GetDirectoryName(exeDir);
            var modulePath4 = parentDir != null ? Path.Combine(parentDir, "modules") : null;
            
            // Find first existing path - comprehensive check
            var modulePath1AltFull = Path.Combine(projectRoot1Alt, "modules");

            if (Directory.Exists(modulePath1))
            {
                _modulePath = modulePath1;
            }
            else if (Directory.Exists(modulePath1AltFull))
            {
                _modulePath = modulePath1AltFull;
            }
            else if (Directory.Exists(modulePath2))
            {
                _modulePath = modulePath2;
            }
            else if (Directory.Exists(modulePath3))
            {
                _modulePath = modulePath3;
            }
            else if (modulePath4 != null && Directory.Exists(modulePath4))
            {
                _modulePath = modulePath4;
            }
            else
            {
                // Final fallback: ensure modules folder is appended
                var currentDir = Directory.GetCurrentDirectory();
                var finalPath = Path.Combine(currentDir, "modules");
                if (Directory.Exists(finalPath))
                {
                    _modulePath = finalPath;
                }
                else
                {
                    // Last resort: use project root + modules
                    _modulePath = Path.Combine(projectRoot1, "modules");
                }
            }
            // Safety check: ensure _modulePath always includes \modules
            if (string.IsNullOrEmpty(_modulePath) || !_modulePath.EndsWith("modules", StringComparison.OrdinalIgnoreCase))
            {
                var safePath = Path.Combine(projectRoot1, "modules");
                _modulePath = Directory.Exists(safePath) ? safePath : Path.Combine(Directory.GetCurrentDirectory(), "modules");
            }
        }
        
        public async Task<T> ExecuteAsync<T>(string moduleName, string functionName, Dictionary<string, object>? parameters = null)
        {
            return await Task.Run(() =>
            {
                using (var ps = PowerShell.Create())
                {
                    // Completely suppress all PowerShell output streams
                    ps.Runspace.SessionStateProxy.SetVariable("ErrorActionPreference", "SilentlyContinue");
                    ps.Runspace.SessionStateProxy.SetVariable("WarningPreference", "SilentlyContinue");
                    ps.Streams.Error.Clear();
                    
                    // Import module
                    ps.AddCommand("Import-Module")
                      .AddParameter("Name", Path.Combine(_modulePath, $"{moduleName}.psm1"))
                      .AddParameter("ErrorAction", "SilentlyContinue");
                    ps.Invoke();
                    // Clear Diagnostics.dll errors immediately if all errors are Diagnostics-related
                    if (ps.HadErrors)
                    {
                        var importErrors = ps.Streams.Error.ReadAll();
                        if (importErrors.All(e => IsDiagnosticsError(e.ToString())))
                        {
                            ps.Streams.Error.Clear();
                        }
                    }
                    ps.Commands.Clear();
                    
                    // Build function call
                    ps.AddCommand(functionName);
                    
                    if (parameters != null)
                    {
                        foreach (var param in parameters)
                        {
                            if (param.Value != null)
                            {
                                ps.AddParameter(param.Key, param.Value);
                            }
                        }
                    }
                    
                    // Execute and get results
                    var results = ps.Invoke();
                    
                    if (ps.HadErrors)
                    {
                        var errors = ps.Streams.Error.ReadAll();
                        var criticalErrors = FilterDiagnosticsErrors(errors);
                        
                        if (criticalErrors.Any())
                        {
                            throw new Exception($"PowerShell error: {string.Join("; ", criticalErrors.Select(e => e.ToString()))}");
                        }
                        // Diagnostics errors ignored - continue execution
                    }
                    
                    // Convert to JSON and back to type
                    var json = JsonConvert.SerializeObject(results);
                    var deserialized = JsonConvert.DeserializeObject<T>(json);
                    if (deserialized == null)
                    {
                        throw new InvalidOperationException($"Failed to deserialize result from {functionName}");
                    }
                    return deserialized;
                }
            });
        }
        
        /// <summary>
        /// Helper method to load a PowerShell module with execution policy bypass
        /// </summary>
        private void LoadModuleWithBypass(PowerShell ps, string moduleFile, string moduleName)
        {
            WriteDebugLog($"Loading dependency module: {moduleName}");
            bool moduleLoaded = false;
            
            // Method 1: Try Import-Module with Force and Global scope
            try
            {
                ps.AddScript($@"
                    $ErrorActionPreference = 'SilentlyContinue'
                    $WarningPreference = 'SilentlyContinue'
                    Import-Module -Name '{moduleFile.Replace("'", "''")}' -Force -ErrorAction SilentlyContinue -WarningAction SilentlyContinue -Global
                ");
                ps.Invoke();
                ps.Commands.Clear();
                
                // Verify module loaded
                ps.AddScript($"Get-Module -Name '{Path.GetFileNameWithoutExtension(moduleFile)}' -ErrorAction SilentlyContinue");
                var moduleCheck = ps.Invoke();
                ps.Commands.Clear();
                
                if (moduleCheck != null && moduleCheck.Count > 0)
                {
                    moduleLoaded = true;
                    WriteDebugLog($"Dependency module {moduleName} loaded using Import-Module");
                }
                
                // Clear Diagnostics errors
                var errors = ps.Streams.Error.ReadAll();
                if (errors.All(e => IsDiagnosticsError(e.ToString()) || 
                    e.ToString().Contains("execution policy", StringComparison.OrdinalIgnoreCase)))
                {
                    ps.Streams.Error.Clear();
                }
            }
            catch (Exception importEx)
            {
                WriteDebugLog($"Import-Module failed for {moduleName}: {importEx.Message}");
                ps.Commands.Clear();
                ps.Streams.Error.Clear();
            }
            
            // Method 2: Try dot-sourcing if Import-Module failed
            if (!moduleLoaded)
            {
                try
                {
                    // Use variable to avoid exposing file path in script string
                    ps.Runspace.SessionStateProxy.SetVariable("ModuleFilePath", moduleFile);
                    ps.AddScript(@"
                        $ErrorActionPreference = 'SilentlyContinue'
                        $WarningPreference = 'SilentlyContinue'
                        . $ModuleFilePath
                    ");
                    ps.Invoke();
                    ps.Commands.Clear();
                    moduleLoaded = true;
                    WriteDebugLog($"Dependency module {moduleName} loaded using dot-source");
                    ps.Streams.Error.Clear();
                }
                catch (Exception dotSourceEx)
                {
                    WriteDebugLog($"Dot-source failed for {moduleName}: {dotSourceEx.Message}");
                    ps.Commands.Clear();
                    ps.Streams.Error.Clear();
                }
            }
            
            if (!moduleLoaded)
            {
                WriteDebugLog($"WARNING: Failed to load dependency module {moduleName}, but continuing...");
            }
        }
        
        /// <summary>
        /// Executes a PowerShell script file and returns JSON output
        /// This uses Process.Start to avoid runspace issues
        /// </summary>
        public async Task<string> ExecuteScriptAsync(string scriptName)
        {
            WriteDebugLog($"ExecuteScriptAsync called: script={scriptName}");
            return await Task.Run(() =>
            {
                try
                {
                    // Find PowerShell executable
                    var psPath = FindPowerShellExecutable();
                    if (psPath == null)
                    {
                        WriteDebugLog("ERROR: PowerShell executable not found");
                        return "[]";
                    }

                    // Find script file
                    var exeDir = AppDomain.CurrentDomain.BaseDirectory;
                    var scriptPath = Path.Combine(exeDir, "Scripts", scriptName);
                    
                    // Also try relative to project root
                    if (!File.Exists(scriptPath))
                    {
                        var projectRoot = Path.GetFullPath(Path.Combine(exeDir, "..", "..", "..", ".."));
                        scriptPath = Path.Combine(projectRoot, "src", "Scripts", scriptName);
                    }
                    
                    if (!File.Exists(scriptPath))
                    {
                        WriteDebugLog($"ERROR: Script file not found: {scriptName}");
                        return "[]";
                    }

                    WriteDebugLog($"Executing PowerShell script: {scriptPath}");

                    // Execute script - set working directory to script's directory so relative paths work
                    var scriptDir = Path.GetDirectoryName(scriptPath);
                    var processInfo = new ProcessStartInfo
                    {
                        FileName = psPath,
                        Arguments = $"-NoProfile -ExecutionPolicy Bypass -File \"{scriptPath}\"",
                        UseShellExecute = false,
                        RedirectStandardOutput = true,
                        RedirectStandardError = true,
                        CreateNoWindow = true,
                        WindowStyle = ProcessWindowStyle.Hidden,
                        WorkingDirectory = scriptDir ?? AppDomain.CurrentDomain.BaseDirectory
                    };

                    using (var process = Process.Start(processInfo))
                    {
                        if (process == null)
                        {
                            WriteDebugLog("ERROR: Failed to start PowerShell process");
                            return "[]";
                        }

                        WriteDebugLog($"PowerShell process started, PID: {process.Id}");
                        WriteDebugLog($"Working directory: {processInfo.WorkingDirectory}");

                        // Read output asynchronously to avoid deadlocks
                        var outputBuilder = new System.Text.StringBuilder();
                        var errorBuilder = new System.Text.StringBuilder();
                        
                        process.OutputDataReceived += (sender, e) =>
                        {
                            if (!string.IsNullOrEmpty(e.Data))
                            {
                                outputBuilder.AppendLine(e.Data);
                            }
                        };
                        
                        process.ErrorDataReceived += (sender, e) =>
                        {
                            if (!string.IsNullOrEmpty(e.Data))
                            {
                                errorBuilder.AppendLine(e.Data);
                            }
                        };
                        
                        process.BeginOutputReadLine();
                        process.BeginErrorReadLine();
                        
                        process.WaitForExit(30000); // 30 second timeout
                        
                        if (!process.HasExited)
                        {
                            WriteDebugLog("WARNING: PowerShell process did not exit within 30 seconds, killing it");
                            process.Kill();
                            process.WaitForExit(5000);
                        }

                        var output = outputBuilder.ToString();
                        var errors = errorBuilder.ToString();

                        WriteDebugLog($"PowerShell script exited with code {process.ExitCode}");
                        WriteDebugLog($"Output length: {output.Length}, Errors length: {errors.Length}");

                        // Log errors/warnings even if exit code is 0 (scripts output warnings to stderr)
                        if (!string.IsNullOrEmpty(errors))
                        {
                            WriteDebugLog($"PowerShell stderr output (first 1000 chars): {errors.Substring(0, Math.Min(1000, errors.Length))}");
                        }

                        if (process.ExitCode != 0)
                        {
                            WriteDebugLog($"PowerShell script exited with non-zero code: {process.ExitCode}");
                            if (!string.IsNullOrEmpty(errors))
                            {
                                WriteDebugLog($"PowerShell errors: {errors}");
                            }
                            // Still try to parse output in case script output JSON before erroring
                        }

                        if (string.IsNullOrWhiteSpace(output))
                        {
                            WriteDebugLog("PowerShell script returned empty output");
                            if (!string.IsNullOrEmpty(errors))
                            {
                                WriteDebugLog($"Check stderr for details: {errors}");
                            }
                            // Log first few lines of output even if empty to debug
                            WriteDebugLog($"Output preview (first 200 chars): {output.Substring(0, Math.Min(200, output.Length))}");
                            return "[]";
                        }

                        // Strip ANSI color codes from output (PowerShell 7+ adds these)
                        var cleanedOutput = System.Text.RegularExpressions.Regex.Replace(
                            output,
                            @"\x1B\[[0-9;]*[a-zA-Z]",
                            "",
                            System.Text.RegularExpressions.RegexOptions.Compiled
                        );
                        
                        // Extract JSON from output - it might have warnings/debug messages before/after it
                        // Strategy: Find the largest valid JSON array/object in the output
                        string jsonOutput = cleanedOutput.Trim();
                        
                        // Try multiple strategies to extract JSON
                        // Strategy 1: Find JSON by matching brackets/braces (handles nested JSON)
                        var jsonStart = -1;
                        var jsonEnd = -1;
                        
                        // Find first [ or {
                        for (int i = 0; i < cleanedOutput.Length; i++)
                        {
                            if (cleanedOutput[i] == '[' || cleanedOutput[i] == '{')
                            {
                                jsonStart = i;
                                break;
                            }
                        }
                        
                        if (jsonStart >= 0)
                        {
                            // Found start, now find matching end bracket/brace
                            char startChar = cleanedOutput[jsonStart];
                            char endChar = startChar == '[' ? ']' : '}';
                            int depth = 0;
                            bool inString = false;
                            bool escapeNext = false;
                            
                            for (int i = jsonStart; i < cleanedOutput.Length; i++)
                            {
                                char c = cleanedOutput[i];
                                
                                if (escapeNext)
                                {
                                    escapeNext = false;
                                    continue;
                                }
                                
                                if (c == '\\' && inString)
                                {
                                    escapeNext = true;
                                    continue;
                                }
                                
                                if (c == '"' && !escapeNext)
                                {
                                    inString = !inString;
                                    continue;
                                }
                                
                                if (!inString)
                                {
                                    if (c == startChar) depth++;
                                    else if (c == endChar)
                                    {
                                        depth--;
                                        if (depth == 0)
                                        {
                                            jsonEnd = i + 1;
                                            break;
                                        }
                                    }
                                }
                            }
                            
                            if (jsonEnd > jsonStart)
                            {
                                jsonOutput = cleanedOutput.Substring(jsonStart, jsonEnd - jsonStart).Trim();
                                if (jsonStart > 0)
                                {
                                    var skippedText = cleanedOutput.Substring(0, jsonStart).Trim();
                                    WriteDebugLog($"Skipped {skippedText.Length} characters of non-JSON output before JSON start");
                                    WriteDebugLog($"Skipped text preview: {skippedText.Substring(0, Math.Min(200, skippedText.Length))}");
                                }
                            }
                            else
                            {
                                // JSON start found but no matching end - try to extract from start to end of string
                                jsonOutput = cleanedOutput.Substring(jsonStart).Trim();
                                WriteDebugLog("WARNING: Found JSON start but couldn't find matching end bracket/brace - using rest of output");
                            }
                        }
                        else
                        {
                            // Strategy 2: Try to find JSON by looking for JSON-like patterns
                            // Look for lines that start with [ or {
                            var lines = cleanedOutput.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
                            foreach (var line in lines)
                            {
                                var trimmed = line.Trim();
                                if (trimmed.StartsWith("[") || trimmed.StartsWith("{"))
                                {
                                    jsonOutput = trimmed;
                                    WriteDebugLog("Found JSON on a line starting with [ or {");
                                    break;
                                }
                            }
                        }
                        
                        WriteDebugLog($"PowerShell script returned {jsonOutput.Length} characters (after ANSI strip and JSON extraction)");
                        WriteDebugLog($"Output preview (first 500 chars): {jsonOutput.Substring(0, Math.Min(500, jsonOutput.Length))}");

                        // Validate JSON
                        if (!jsonOutput.StartsWith("[") && !jsonOutput.StartsWith("{"))
                        {
                            WriteDebugLog($"WARNING: Output doesn't look like JSON: {jsonOutput.Substring(0, Math.Min(100, jsonOutput.Length))}");
                            if (!string.IsNullOrEmpty(errors))
                            {
                                WriteDebugLog($"Stderr had: {errors.Substring(0, Math.Min(500, errors.Length))}");
                            }
                            return "[]";
                        }

                        // Check if it's an empty array/object
                        if (jsonOutput == "[]" || jsonOutput == "{}")
                        {
                            WriteDebugLog("Script returned empty JSON array/object");
                            if (!string.IsNullOrEmpty(errors))
                            {
                                WriteDebugLog($"Possible reason from stderr: {errors.Substring(0, Math.Min(1000, errors.Length))}");
                            }
                        }
                        else
                        {
                            WriteDebugLog($"Successfully got JSON output with {jsonOutput.Length} characters");
                        }

                        return jsonOutput;
                    }
                }
                catch (Exception ex)
                {
                    WriteDebugLog($"EXCEPTION in ExecuteScriptAsync: {ex.GetType().Name}: {ex.Message}");
                    WriteDebugLog($"Stack trace: {ex.StackTrace}");
                    return "[]";
                }
            });
        }

        private string? FindPowerShellExecutable()
        {
            // Try PowerShell 7+ first (pwsh.exe)
            var pwshPaths = new[]
            {
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "PowerShell", "7", "pwsh.exe"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "PowerShell", "7", "pwsh.exe"),
                "pwsh.exe" // In PATH
            };

            foreach (var path in pwshPaths)
            {
                if (File.Exists(path) || path == "pwsh.exe")
                {
                    try
                    {
                        var testProcess = Process.Start(new ProcessStartInfo
                        {
                            FileName = path,
                            Arguments = "-NoProfile -Command \"exit 0\"",
                            UseShellExecute = false,
                            RedirectStandardOutput = true,
                            RedirectStandardError = true,
                            CreateNoWindow = true
                        });
                        if (testProcess != null)
                        {
                            testProcess.WaitForExit(2000);
                            if (testProcess.ExitCode == 0)
                            {
                                WriteDebugLog($"Found PowerShell executable: {path}");
                                return path;
                            }
                        }
                    }
                    catch { }
                }
            }

            // Fallback to Windows PowerShell (powershell.exe)
            var psPaths = new[]
            {
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe"),
                "powershell.exe" // In PATH
            };

            foreach (var path in psPaths)
            {
                if (File.Exists(path) || path == "powershell.exe")
                {
                    WriteDebugLog($"Found PowerShell executable (fallback): {path}");
                    return path;
                }
            }

            WriteDebugLog("ERROR: No PowerShell executable found");
            return null;
        }

        [Obsolete("Use ExecuteScriptAsync instead")]
        public async Task<string> ExecuteJsonAsync(string moduleName, string functionName, Dictionary<string, object>? parameters = null)
        {
            WriteDebugLog($"ExecuteJsonAsync called: module={moduleName}, function={functionName}");
            return await Task.Run(() =>
            {
                try
                {
                    // Wrap entire execution to prevent file paths from leaking to Windows
                    // Windows may intercept exceptions containing .psm1 file paths and try to open them
                    WriteDebugLog($"Creating PowerShell instance...");
                    PowerShell ps;
                    Runspace? runspace = null;
                    InitialSessionState iss;
                    
                    // Try to create default session state - this may fail due to Diagnostics.dll
                    try
                    {
                        iss = InitialSessionState.CreateDefault();
                        WriteDebugLog($"Default session state created successfully");
                    }
                    catch (Exception createDefaultEx)
                    {
                        // If Diagnostics.dll error during CreateDefault(), use fallback
                        if (createDefaultEx.Message.Contains("Diagnostics") || createDefaultEx.Message.Contains("Diagnostics.dll") || 
                            createDefaultEx.GetType().Name.Contains("PSSnapIn") || createDefaultEx.GetType().Name.Contains("PSSnapInException"))
                        {
                            WriteDebugLog($"CreateDefault() failed (Diagnostics.dll - using fallback): {createDefaultEx.Message}");
                            // Try CreateDefault2() if available, otherwise create minimal with language
                            try
                            {
                                // Try CreateDefault2 which might not include Diagnostics
                                var method = typeof(InitialSessionState).GetMethod("CreateDefault2", System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Static);
                                if (method != null)
                                {
                                    var result = method.Invoke(null, null);
                                    if (result is InitialSessionState default2Iss)
                                    {
                                        iss = default2Iss;
                                        WriteDebugLog($"Using CreateDefault2() session state");
                                    }
                                    else
                                    {
                                        throw new InvalidOperationException("CreateDefault2() returned null or invalid type");
                                    }
                                }
                                else
                                {
                                    // Fallback: create minimal session state and add language support manually
                                    iss = InitialSessionState.Create();
                                    // Add language mode - this enables PowerShell syntax
                                    iss.LanguageMode = PSLanguageMode.FullLanguage;
                                    WriteDebugLog($"Using minimal session state with FullLanguage mode");
                                }
                            }
                            catch (Exception fallbackEx)
                            {
                                WriteDebugLog($"Fallback session state creation also failed: {fallbackEx.Message}");
                                throw; // Re-throw if fallback also fails
                            }
                        }
                        else
                        {
                            throw; // Re-throw if it's a different error
                        }
                    }
                    
                    // Now create and open the runspace
                    try
                    {
                        runspace = RunspaceFactory.CreateRunspace(iss);
                        runspace.Open();
                        WriteDebugLog($"Runspace created and opened successfully");
                    }
                    catch (Exception runspaceEx)
                    {
                        WriteDebugLog($"Runspace creation/opening failed: {runspaceEx.Message}");
                        throw; // Re-throw runspace errors
                    }
                    
                    ps = PowerShell.Create();
                    ps.Runspace = runspace;
                    WriteDebugLog($"PowerShell instance created successfully");
                    
                    // Ensure Microsoft.PowerShell.Utility is loaded (needed for ConvertTo-Json)
                    // This is especially important when using CreateDefault2() which may not include it
                    try
                    {
                        WriteDebugLog($"Ensuring Microsoft.PowerShell.Utility module is loaded...");
                        ps.AddScript(@"
                            $ErrorActionPreference = 'SilentlyContinue'
                            if (-not (Get-Module -Name Microsoft.PowerShell.Utility -ErrorAction SilentlyContinue)) {
                                Import-Module Microsoft.PowerShell.Utility -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
                            }
                        ");
                        ps.Invoke();
                        ps.Commands.Clear();
                        ps.Streams.Error.Clear();
                        WriteDebugLog($"Microsoft.PowerShell.Utility module check completed");
                    }
                    catch (Exception utilEx)
                    {
                        WriteDebugLog($"Warning: Could not ensure Microsoft.PowerShell.Utility is loaded: {utilEx.Message}");
                        ps.Commands.Clear();
                        ps.Streams.Error.Clear();
                    }
                    
                    try
                    {
                        var moduleFile = Path.Combine(_modulePath, $"{moduleName}.psm1");
                        WriteDebugLog($"Module file: {moduleName}.psm1");
                        
                        if (!File.Exists(moduleFile))
                        {
                            // Don't expose file paths - return empty result instead of throwing
                            // This prevents Windows from intercepting and trying to open the file
                            WriteDebugLog($"ERROR: Module file not found (path sanitized in log)");
                            WriteDebugLog($"Returning empty result for missing module: {moduleName}");
                            return "[]";
                        }
                        
                        WriteDebugLog($"Module file exists, proceeding...");
                        
                        // Completely suppress all PowerShell output streams
                        ps.Runspace.SessionStateProxy.SetVariable("ErrorActionPreference", "SilentlyContinue");
                        ps.Runspace.SessionStateProxy.SetVariable("WarningPreference", "SilentlyContinue");
                        ps.Streams.Error.Clear();
                        
                        // Set execution policy for current process - try multiple methods
                        WriteDebugLog($"Setting execution policy to Bypass...");
                        try
                        {
                            // Method 1: Use Set-ExecutionPolicy command
                            ps.AddScript("Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force");
                            ps.Invoke();
                            var policyErrors = ps.Streams.Error.ReadAll();
                            var criticalPolicyErrors = FilterDiagnosticsErrors(policyErrors);
                            if (criticalPolicyErrors.Any())
                            {
                                WriteDebugLog($"Set-ExecutionPolicy had errors: {string.Join("; ", criticalPolicyErrors.Select(e => e.ToString()))}");
                            }
                            // Clear Diagnostics errors
                            if (policyErrors.All(e => IsDiagnosticsError(e.ToString())))
                            {
                                ps.Streams.Error.Clear();
                            }
                            ps.Commands.Clear();
                            
                            // Verify execution policy was set
                            ps.AddScript("Get-ExecutionPolicy -Scope Process");
                            var policyResult = ps.Invoke();
                            ps.Commands.Clear();
                            if (policyResult != null && policyResult.Count > 0)
                            {
                                var currentPolicy = policyResult[0]?.ToString() ?? "";
                                WriteDebugLog($"Current execution policy (Process scope): {currentPolicy}");
                                if (!currentPolicy.Equals("Bypass", StringComparison.OrdinalIgnoreCase) && 
                                    !currentPolicy.Equals("Unrestricted", StringComparison.OrdinalIgnoreCase))
                                {
                                    WriteDebugLog($"WARNING: Execution policy is {currentPolicy}, may need to set differently");
                                }
                            }
                        }
                        catch (Exception policyEx)
                        {
                            WriteDebugLog($"Failed to set execution policy: {policyEx.Message}");
                            // Continue anyway - might still work
                        }
                    
                    // Import module - use Import-Module with execution policy bypass via script block
                    WriteDebugLog($"Importing module: {moduleName}");
                    bool moduleImported = false;
                    string moduleBaseName = Path.GetFileNameWithoutExtension(moduleFile);
                    
                    // Method 1: Try Import-Module with execution policy bypass using script block
                    // This approach wraps Import-Module in a way that bypasses execution policy
                    try
                    {
                        WriteDebugLog($"Trying Import-Module with execution policy bypass...");
                        // Use variable to avoid exposing file path in script string
                        ps.Runspace.SessionStateProxy.SetVariable("ModuleFilePath", moduleFile);
                        // Use a script block that sets execution policy and imports the module
                        ps.AddScript(@"
                            $ErrorActionPreference = 'SilentlyContinue'
                            $WarningPreference = 'SilentlyContinue'
                            $ExecutionContext.InvokeCommand.InvokeScript('Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force', $false, [System.Management.Automation.PSInvocationState]::NotStarted, $null)
                            Import-Module -Name $ModuleFilePath -Force -ErrorAction SilentlyContinue -WarningAction SilentlyContinue -Global
                        ");
                        ps.Invoke();
                        ps.Commands.Clear();
                        
                        // Check if module was imported or functions are available
                        ps.AddScript($"Get-Module -Name '{moduleBaseName}' -ErrorAction SilentlyContinue");
                        var moduleCheck = ps.Invoke();
                        ps.Commands.Clear();
                        
                        // Also check if the function exists (for cases where module loads but doesn't register)
                        ps.AddScript($"Get-Command {functionName} -ErrorAction SilentlyContinue");
                        var funcCheck = ps.Invoke();
                        ps.Commands.Clear();
                        
                        if ((moduleCheck != null && moduleCheck.Count > 0) || (funcCheck != null && funcCheck.Count > 0))
                        {
                            moduleImported = true;
                            WriteDebugLog($"Module imported successfully using Import-Module");
                        }
                        else
                        {
                            WriteDebugLog($"Import-Module completed but module/function not found in checks");
                        }
                        
                        // Clear any execution policy errors
                        var importErrors = ps.Streams.Error.ReadAll();
                        if (importErrors.All(e => IsDiagnosticsError(e.ToString()) || 
                            e.ToString().Contains("execution policy", StringComparison.OrdinalIgnoreCase)))
                        {
                            ps.Streams.Error.Clear();
                        }
                    }
                    catch (Exception importEx)
                    {
                        WriteDebugLog($"Import-Module method failed: {importEx.Message}");
                        ps.Commands.Clear();
                        ps.Streams.Error.Clear();
                    }
                    
                    // Method 2: Try dot-sourcing (simple approach - just dot-source the file)
                    if (!moduleImported)
                    {
                        try
                        {
                            WriteDebugLog($"Trying dot-source method...");
                            // Read file content in C# and pass to PowerShell as string
                            // This prevents Windows from intercepting file access
                            // PowerShell never directly accesses the file path
                            try
                            {
                                var moduleContent = System.IO.File.ReadAllText(moduleFile);
                                // Pass content as a variable - PowerShell executes it without file access
                                ps.Runspace.SessionStateProxy.SetVariable("ModuleContent", moduleContent);
                                ps.AddScript(@"
                                    $ErrorActionPreference = 'SilentlyContinue'
                                    $WarningPreference = 'SilentlyContinue'
                                    $InformationPreference = 'SilentlyContinue'
                                    $VerbosePreference = 'SilentlyContinue'
                                    $DebugPreference = 'SilentlyContinue'
                                    $ProgressPreference = 'SilentlyContinue'
                                    # Execute module content using dot-sourcing syntax with script block
                                    # Dot-sourcing (.) executes in current scope, ensuring functions are available
                                    $scriptBlock = [scriptblock]::Create($ModuleContent)
                                    . $scriptBlock
                                ");
                                var dotSourceResults = ps.Invoke();
                                ps.Commands.Clear();
                            }
                            catch (System.IO.IOException ioEx)
                            {
                                // File access error - don't expose path
                                WriteDebugLog($"File read error (path sanitized): {ioEx.GetType().Name}");
                                ps.Commands.Clear();
                                throw new Exception($"Failed to load module {moduleName}");
                            }
                            
                            // Clear ALL streams to prevent any content from leaking
                            ps.Streams.Error.Clear();
                            ps.Streams.Warning.Clear();
                            ps.Streams.Information.Clear();
                            ps.Streams.Verbose.Clear();
                            ps.Streams.Debug.Clear();
                            
                            // Verify function is available after execution
                            // Export-ModuleMember doesn't work with script blocks, but dot-sourcing should make functions available
                            ps.AddScript($"Get-Command {functionName} -ErrorAction SilentlyContinue -All | Select-Object -First 1 Name");
                            var funcCheck = ps.Invoke();
                            ps.Commands.Clear();
                            
                            if (funcCheck != null && funcCheck.Count > 0)
                            {
                                moduleImported = true;
                                WriteDebugLog($"Module loaded successfully - function {functionName} is available");
                            }
                            else
                            {
                                // Function not found - try listing all functions to debug
                                ps.AddScript("Get-ChildItem Function: | Where-Object { $_.Name -like '*S1*' -or $_.Name -like '*Perch*' } | Select-Object -First 5 Name");
                                var allFuncs = ps.Invoke();
                                ps.Commands.Clear();
                                if (allFuncs != null && allFuncs.Count > 0)
                                {
                                    var funcNames = string.Join(", ", allFuncs.Select(f => f.ToString()));
                                    WriteDebugLog($"Found functions: {funcNames}");
                                }
                                WriteDebugLog($"WARNING: Function {functionName} not found after loading, but proceeding anyway");
                                // Still proceed - function might be available at runtime despite check failing
                                moduleImported = true;
                            }
                        }
                        catch (Exception dotSourceEx)
                        {
                            // Don't expose file paths in error messages
                            var safeMsg = dotSourceEx.Message.Replace(".psm1", "[module]");
                            WriteDebugLog($"Dot-source method failed: {safeMsg}");
                            ps.Commands.Clear();
                            ps.Streams.Error.Clear();
                        }
                    }
                    
                    if (!moduleImported)
                    {
                        // Last check: verify function exists anyway (might be available even if checks failed)
                        ps.AddScript($"Get-Command {functionName} -ErrorAction SilentlyContinue");
                        var finalCheck = ps.Invoke();
                        ps.Commands.Clear();
                        if (finalCheck != null && finalCheck.Count > 0)
                        {
                            WriteDebugLog($"Function {functionName} is available, proceeding despite module check failure");
                            moduleImported = true;
                        }
                        else
                        {
                            // Even if Get-Command doesn't find it, the function might still be available
                            // PowerShell sometimes has timing issues with function discovery after dot-sourcing
                            // Let's proceed anyway - if the function doesn't exist, we'll get a better error when we try to call it
                            WriteDebugLog($"WARNING: Function {functionName} not found via Get-Command, but proceeding anyway - may be available at runtime");
                            moduleImported = true; // Proceed optimistically
                        }
                    }
                    
                    if (ps.HadErrors)
                    {
                        var errors = ps.Streams.Error.ReadAll();
                        var criticalErrors = FilterDiagnosticsErrors(errors);
                        
                        // Clear Diagnostics errors from stream
                        if (errors.All(e => IsDiagnosticsError(e.ToString())))
                        {
                            ps.Streams.Error.Clear();
                        }
                        
                        // Only throw if there are critical errors (not Diagnostics-related)
                        if (criticalErrors.Any())
                        {
                            throw new Exception($"Failed to import module {moduleName}: {string.Join("; ", criticalErrors.Select(e => e.ToString()))}");
                        }
                        // Diagnostics errors ignored - continue execution
                    }
                    else
                    {
                        // Clear any Diagnostics errors that might have been added
                        ps.Streams.Error.Clear();
                    }
                    
                    ps.Commands.Clear();
                    
                    // Initialize config if needed (for ThreatHuntConfig)
                    if (moduleName == "ThreatHuntConfig")
                    {
                        ps.AddCommand("Initialize-ThreatHuntConfig");
                        ps.Invoke();
                        // Clear Diagnostics errors
                        var initErrors = ps.Streams.Error.ReadAll();
                        if (initErrors.All(e => IsDiagnosticsError(e.ToString())))
                        {
                            ps.Streams.Error.Clear();
                        }
                        ps.Commands.Clear();
                    }
                    
                    // For SentinelOneHunter and PerchHunter, ensure ThreatHuntConfig and ConnectionManager are loaded
                    // since they need it when Platform parameter is used
                    if (moduleName == "SentinelOneHunter" || moduleName == "PerchHunter")
                    {
                        // First ensure ThreatHuntConfig is loaded and initialized
                        var configModuleFile = Path.Combine(_modulePath, "ThreatHuntConfig.psm1");
                        if (File.Exists(configModuleFile))
                        {
                            LoadModuleWithBypass(ps, configModuleFile, "ThreatHuntConfig");
                            
                            // Initialize ThreatHuntConfig - Get-PlatformConnection needs it
                            // Don't fail if config file doesn't exist - Get-PlatformConnection will handle it
                            // First check if the function exists (dot-sourcing might not expose it the same way)
                            ps.AddScript("Get-Command Initialize-ThreatHuntConfig -ErrorAction SilentlyContinue");
                            var cmdCheck = ps.Invoke();
                            ps.Commands.Clear();
                            
                            if (cmdCheck != null && cmdCheck.Count > 0)
                            {
                                WriteDebugLog($"Initialize-ThreatHuntConfig command found, calling it...");
                                ps.AddCommand("Initialize-ThreatHuntConfig")
                                  .AddParameter("ErrorAction", "SilentlyContinue");
                                ps.Invoke();
                                // Check for errors - if config file missing, that's OK for discovery
                                var initErrors = ps.Streams.Error.ReadAll();
                                var criticalInitErrors = initErrors.Where(e => {
                                    var err = e.ToString().ToLowerInvariant();
                                    return !IsDiagnosticsError(err) &&
                                           !err.Contains("configuration file not found") &&
                                           !err.Contains("config.json") &&
                                           !err.Contains("is not recognized");
                                }).ToList();
                                
                                if (criticalInitErrors.Any())
                                {
                                    WriteDebugLog($"ThreatHuntConfig init errors: {string.Join("; ", criticalInitErrors)}");
                                }
                                
                                // Clear all errors - Get-PlatformConnection will initialize if needed
                                ps.Streams.Error.Clear();
                                ps.Commands.Clear();
                            }
                            else
                            {
                                WriteDebugLog($"Initialize-ThreatHuntConfig not found after loading module - functions may not be exposed. This is OK for discovery.");
                                // Clear any errors from the command check
                                ps.Streams.Error.Clear();
                            }
                        }
                        
                        // Then ensure ConnectionManager is loaded
                        var connModuleFile = Path.Combine(_modulePath, "ConnectionManager.psm1");
                        if (File.Exists(connModuleFile))
                        {
                            LoadModuleWithBypass(ps, connModuleFile, "ConnectionManager");
                        }
                    }
                    
                    // Check if ConvertTo-Json is available before building command pipeline
                    ps.AddScript("Get-Command ConvertTo-Json -ErrorAction SilentlyContinue | Select-Object -First 1 Name");
                    var jsonCmdCheck = ps.Invoke();
                    ps.Commands.Clear();
                    
                    bool useConvertToJson = (jsonCmdCheck != null && jsonCmdCheck.Count > 0);
                    
                    // Build function call
                    ps.AddCommand(functionName);
                    
                    if (parameters != null)
                    {
                        foreach (var param in parameters)
                        {
                            if (param.Value != null)
                            {
                                ps.AddParameter(param.Key, param.Value);
                            }
                        }
                    }
                    
                    if (useConvertToJson)
                    {
                        // ConvertTo-Json is available - pipe to it
                        ps.AddCommand("ConvertTo-Json")
                          .AddParameter("Depth", 10)
                          .AddParameter("Compress", false);
                        WriteDebugLog($"Executing PowerShell command: {functionName} | ConvertTo-Json");
                    }
                    else
                    {
                        // ConvertTo-Json not available - get raw results and serialize in C#
                        WriteDebugLog($"WARNING: ConvertTo-Json not available, will serialize results in C#");
                        WriteDebugLog($"Executing PowerShell command: {functionName}");
                    }
                    
                    // Capture all output streams
                    System.Diagnostics.Stopwatch sw = System.Diagnostics.Stopwatch.StartNew();
                    System.Collections.ObjectModel.Collection<System.Management.Automation.PSObject>? results = null;
                    try
                    {
                        results = ps.Invoke();
                    }
                    catch (System.Management.Automation.CommandNotFoundException cmdEx)
                    {
                        // CommandNotFoundException often contains file paths - sanitize them immediately
                        sw.Stop();
                        var safeMsg = cmdEx.Message.Replace(".psm1", "[module]");
                        var pathPattern = @"[A-Z]:\\[^\s]+\.psm1";
                        safeMsg = System.Text.RegularExpressions.Regex.Replace(safeMsg, pathPattern, "[module file]");
                        // Also sanitize the inner exception if present
                        if (cmdEx.InnerException != null)
                        {
                            var innerMsg = cmdEx.InnerException.Message.Replace(".psm1", "[module]");
                            innerMsg = System.Text.RegularExpressions.Regex.Replace(innerMsg, pathPattern, "[module file]");
                            safeMsg = $"{safeMsg} ({innerMsg})";
                        }
                        throw new Exception($"Command '{functionName}' not found. {safeMsg}");
                    }
                    sw.Stop();
                    
                    WriteDebugLog($"PowerShell Invoke() completed in {sw.ElapsedMilliseconds}ms. Results count: {results?.Count ?? 0}");
                    WriteDebugLog($"PowerShell HadErrors: {ps.HadErrors}");
                    
                    // Also check for any output in the output stream
                    var output = ps.Streams.Information.ReadAll();
                    foreach (var info in output)
                    {
                        System.Diagnostics.Debug.WriteLine($"PowerShell Info: {info}");
                    }
                    
                    // Debug: Log raw results
                    System.Diagnostics.Debug.WriteLine($"PowerShell function {functionName} returned {results?.Count ?? 0} JSON results");
                    
                    // Always check for errors, but only throw for non-Diagnostics errors
                    if (ps.HadErrors)
                    {
                        var errors = ps.Streams.Error.ReadAll();
                        var criticalErrors = FilterDiagnosticsErrors(errors);
                        
                        // Log all errors for debugging
                        foreach (var err in errors)
                        {
                            System.Diagnostics.Debug.WriteLine($"PowerShell Error: {err}");
                        }
                        
                        // Clear Diagnostics errors from stream - they're non-critical
                        if (errors.All(e => IsDiagnosticsError(e.ToString())))
                        {
                            ps.Streams.Error.Clear();
                            // Diagnostics errors only - continue with results
                        }
                        else if (criticalErrors.Any())
                        {
                            // Real errors - sanitize file paths before throwing
                            var errorMsg = string.Join("; ", criticalErrors.Select(e => {
                                var errStr = e.ToString();
                                // Remove file paths that might trigger Windows file associations
                                errStr = errStr.Replace(".psm1", "[module]");
                                var pathPattern = @"[A-Z]:\\[^\s]+\.psm1";
                                errStr = System.Text.RegularExpressions.Regex.Replace(errStr, pathPattern, "[module file]");
                                return errStr;
                            }));
                            System.Diagnostics.Debug.WriteLine($"Critical PowerShell Error: {errorMsg}");
                            throw new Exception($"PowerShell error in {functionName}: {errorMsg}");
                        }
                        // Mixed errors - Diagnostics errors filtered out, continue if no critical errors
                    }
                    else
                    {
                        // Clear any Diagnostics errors that might have been added
                        ps.Streams.Error.Clear();
                    }
                    
                    // Results are either JSON strings (from ConvertTo-Json) or PowerShell objects (to serialize in C#)
                    if (results != null && results.Count > 0)
                    {
                        string jsonString;
                        
                        if (useConvertToJson)
                        {
                            // ConvertTo-Json outputs formatted JSON which may be split across multiple result objects
                            // Each result object might contain one or more lines of JSON
                            // Combine all results, preserving newlines
                            var jsonParts = new List<string>();
                            foreach (var result in results)
                            {
                                if (result != null)
                                {
                                    var str = result.ToString();
                                    if (!string.IsNullOrEmpty(str))
                                    {
                                        jsonParts.Add(str);
                                    }
                                }
                            }
                            
                            // Join with newline (ConvertTo-Json outputs formatted JSON with newlines)
                            jsonString = string.Join("\n", jsonParts);
                            WriteDebugLog($"ConvertTo-Json returned {results.Count} result objects, combined to {jsonParts.Count} parts");
                        }
                        else
                        {
                            // ConvertTo-Json not available - serialize PowerShell objects directly in C#
                            WriteDebugLog($"Serializing {results.Count} PowerShell objects to JSON in C#");
                            jsonString = Newtonsoft.Json.JsonConvert.SerializeObject(results, Newtonsoft.Json.Formatting.Indented);
                        }
                        
                        if (!string.IsNullOrWhiteSpace(jsonString))
                        {
                            // Ensure it's a valid JSON array (ConvertTo-Json might return object for single item)
                            jsonString = jsonString.Trim();
                            
                            // Debug: Log first and last chars to verify structure
                            WriteDebugLog($"JSON starts with: {(jsonString.Length > 0 ? jsonString[0].ToString() : "empty")}, ends with: {(jsonString.Length > 0 ? jsonString[jsonString.Length - 1].ToString() : "empty")}");
                            System.Diagnostics.Debug.WriteLine($"JSON starts with: {(jsonString.Length > 0 ? jsonString[0].ToString() : "empty")}, ends with: {(jsonString.Length > 0 ? jsonString[jsonString.Length - 1].ToString() : "empty")}");
                            
                            if (!jsonString.StartsWith("[") && !jsonString.StartsWith("{"))
                            {
                                // Invalid JSON, return empty array
                                System.Diagnostics.Debug.WriteLine($"Invalid JSON from ConvertTo-Json: {jsonString.Substring(0, Math.Min(100, jsonString.Length))}...");
                                return "[]";
                            }
                            
                            // If it's a single object, wrap it in an array
                            if (jsonString.StartsWith("{"))
                            {
                                jsonString = $"[{jsonString}]";
                            }
                            
                            WriteDebugLog($"JSON Result length: {jsonString.Length}");
                            WriteDebugLog($"JSON Result (first 1000 chars): {jsonString.Substring(0, Math.Min(1000, jsonString.Length))}...");
                            System.Diagnostics.Debug.WriteLine($"JSON Result length: {jsonString.Length}");
                            System.Diagnostics.Debug.WriteLine($"JSON Result (first 1000 chars): {jsonString.Substring(0, Math.Min(1000, jsonString.Length))}...");
                            
                            return jsonString;
                        }
                    }
                    
                    // No results - return empty array
                    WriteDebugLog($"No results from {functionName}, returning empty array");
                    WriteDebugLog($"PowerShell results count: {results?.Count ?? 0}");
                    System.Diagnostics.Debug.WriteLine($"No results from {functionName}, returning empty array");
                    System.Diagnostics.Debug.WriteLine($"PowerShell results count: {results?.Count ?? 0}");
                    if (results != null && results.Count > 0)
                    {
                        WriteDebugLog($"First result type: {results[0]?.GetType()?.Name ?? "null"}");
                        var firstResultStr = results[0]?.ToString() ?? "null";
                        WriteDebugLog($"First result (first 500 chars): {firstResultStr.Substring(0, Math.Min(500, firstResultStr.Length))}...");
                        System.Diagnostics.Debug.WriteLine($"First result type: {results[0]?.GetType()?.Name ?? "null"}");
                        System.Diagnostics.Debug.WriteLine($"First result: {firstResultStr}");
                    }
                    else
                    {
                        WriteDebugLog($"PowerShell Invoke() returned null or empty collection");
                    }
                        return "[]";
                    }
                    finally
                    {
                        ps?.Dispose();
                        runspace?.Dispose();
                    }
                }
                catch (Exception ex)
                {
                    WriteDebugLog($"EXCEPTION in ExecuteJsonAsync: {ex.GetType().Name}: {ex.Message}");
                    WriteDebugLog($"Stack trace: {ex.StackTrace}");
                    
                    // Aggressively sanitize ALL exception messages to prevent Windows from opening .psm1 files
                    // This includes the main message, inner exception, and any file paths
                    string SanitizeMessage(string msg)
                    {
                        if (string.IsNullOrEmpty(msg)) return msg;
                        var sanitized = msg;
                        // Remove .psm1 extensions
                        sanitized = sanitized.Replace(".psm1", "[module]");
                        // Remove full file paths (multiple patterns)
                        sanitized = System.Text.RegularExpressions.Regex.Replace(sanitized, @"[A-Z]:\\[^\s]+\.psm1", "[module file]", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
                        sanitized = System.Text.RegularExpressions.Regex.Replace(sanitized, @"[A-Z]:\\[^\s]+\\modules\\[^\s]+", "[module path]", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
                        // Remove any remaining file path patterns
                        sanitized = System.Text.RegularExpressions.Regex.Replace(sanitized, @"[A-Z]:\\[^\s]+", "[path]", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
                        return sanitized;
                    }
                    
                    var sanitizedMessage = SanitizeMessage(ex.Message);
                    var sanitizedInnerMessage = ex.InnerException != null ? SanitizeMessage(ex.InnerException.Message) : null;
                    
                    // Create completely sanitized exception - don't include inner exception if it has file paths
                    Exception safeException;
                    if (ex.InnerException != null && !string.IsNullOrEmpty(sanitizedInnerMessage))
                    {
                        // Create a new inner exception without file paths
                        var safeInner = new Exception(sanitizedInnerMessage);
                        safeException = new Exception($"PowerShell execution failed: {sanitizedMessage}", safeInner);
                    }
                    else
                    {
                        // No inner exception or it's already sanitized
                        safeException = new Exception($"PowerShell execution failed: {sanitizedMessage}");
                    }
                    
                    throw safeException;
                }
            });
        }
    }
}
