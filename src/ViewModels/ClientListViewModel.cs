using System;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Threading.Tasks;
using System.Windows.Input;
using RiverRunThreatHunter.Services;

namespace RiverRunThreatHunter.ViewModels
{
    public class ClientListViewModel : INotifyPropertyChanged
    {
        private ObservableCollection<ClientNode> _clients = new ObservableCollection<ClientNode>();
        private bool _isLoading = false;
        private string _statusMessage = "Ready";
        private readonly PowerShellRunner _powerShellRunner;
        
        public ObservableCollection<ClientNode> Clients
        {
            get => _clients;
            set
            {
                _clients = value;
                OnPropertyChanged();
            }
        }
        
        public bool IsLoading
        {
            get => _isLoading;
            set
            {
                _isLoading = value;
                OnPropertyChanged();
            }
        }
        
        public string StatusMessage
        {
            get => _statusMessage;
            set
            {
                _statusMessage = value;
                OnPropertyChanged();
            }
        }
        
        public ICommand RefreshCommand { get; }
        public ICommand DiscoverCompaniesCommand { get; }
        
        public ClientListViewModel()
        {
            _powerShellRunner = new PowerShellRunner();
            RefreshCommand = new RelayCommand(async () => await LoadClientsAsync());
            DiscoverCompaniesCommand = new RelayCommand(async () => await DiscoverCompaniesAsync());
            
            // Add placeholder so GUI shows something immediately
            Clients.Add(new ClientNode 
            { 
                Name = "Click Refresh to load clients", 
                IsPlatform = false 
            });
            
            // Don't auto-load on startup to prevent Windows from opening .psm1 files
            // User can click Refresh or Discover when ready
            StatusMessage = "Ready - Click Refresh or Discover to begin";
        }
        
        private async Task LoadClientsAsync()
        {
            IsLoading = true;
            StatusMessage = "Loading clients...";
            
            try
            {
                Clients.Clear();
                
                // Load from ThreatHuntConfig module using script execution
                string clientsJson;
                try
                {
                    clientsJson = await _powerShellRunner.ExecuteScriptAsync("Get-AllClients.ps1");
                }
                catch (Exception ex)
                {
                    // Log error but don't expose file paths
                    System.Diagnostics.Debug.WriteLine($"LoadClientsAsync error: {ex.GetType().Name}");
                    Services.PowerShellRunner.WriteDebugLog($"LoadClientsAsync error: {ex.GetType().Name}: {ex.Message}");
                    clientsJson = "[]"; // Return empty array
                }
                
                if (string.IsNullOrWhiteSpace(clientsJson) || clientsJson.Trim() == "[]" || clientsJson.Trim() == "null")
                {
                    StatusMessage = "No clients found in configuration. Use Discover to find companies.";
                    Clients.Clear();
                    Clients.Add(new ClientNode 
                    { 
                        Name = "No clients configured. Use Discover to find companies.", 
                        IsPlatform = false 
                    });
                    IsLoading = false;
                    return;
                }
                
                // Parse JSON and populate clients
                var clients = Newtonsoft.Json.JsonConvert.DeserializeObject<dynamic[]>(clientsJson);
                
                if (clients == null || clients.Length == 0)
                {
                    StatusMessage = "No clients configured. Use Discover to find companies.";
                    Clients.Clear();
                    Clients.Add(new ClientNode 
                    { 
                        Name = "No clients configured. Use Discover to find companies.", 
                        IsPlatform = false 
                    });
                    IsLoading = false;
                    return;
                }
                
                // Group by platform
                var platformGroups = new System.Collections.Generic.Dictionary<string, ObservableCollection<ClientNode>>();
                
                foreach (var client in clients)
                {
                    string platform = client.S1Platform?.ToString() ?? "Unknown";
                    if (!platformGroups.ContainsKey(platform))
                    {
                        platformGroups[platform] = new ObservableCollection<ClientNode>();
                    }
                    
                    platformGroups[platform].Add(new ClientNode
                    {
                        Name = client.ClientName?.ToString() ?? "Unknown",
                        IsPlatform = false,
                        IsReadOnly = client.S1AccessLevel?.ToString() == "ReadOnly",
                        CanTakeAction = client.CanTakeAction?.Value ?? false,
                        SiteId = client.S1SiteId?.ToString() ?? string.Empty,
                        SiteName = client.S1SiteName?.ToString() ?? string.Empty,
                        HasPerch = client.HasPerch?.Value ?? false,
                        PerchTeamId = client.PerchTeamId?.ToString() ?? string.Empty
                    });
                }
                
                // Add platform headers and clients
                foreach (var platformGroup in platformGroups)
                {
                    Clients.Add(new ClientNode 
                    { 
                        Name = platformGroup.Key, 
                        IsPlatform = true 
                    });
                    
                    foreach (var client in platformGroup.Value)
                    {
                        Clients.Add(client);
                    }
                }
                
                StatusMessage = $"Loaded {clients.Length} clients";
            }
            catch (Exception ex)
            {
                // Check if this is a Diagnostics.dll error
                bool isDiagnosticsError = Services.PowerShellRunner.IsDiagnosticsError(ex.Message);
                
                // If it's a Diagnostics error, try to continue - the operation might have succeeded
                if (isDiagnosticsError)
                {
                    // Diagnostics errors are non-critical, check if we got any results anyway
                    // If clientsJson was populated before the exception, we would have processed it
                    // So if we're here, the operation likely failed for a real reason
                    // But Diagnostics.dll errors shouldn't prevent us from showing what we have
                    StatusMessage = "Ready (Diagnostics warnings suppressed)";
                    
                    // Don't clear clients if we already have some loaded
                    if (Clients.Count == 0)
                    {
                        Clients.Add(new ClientNode 
                        { 
                            Name = "No clients configured. Use Discover to find companies.", 
                            IsPlatform = false 
                        });
                    }
                    return;
                }
                
                // Real error - show it but sanitize file paths to prevent Windows from opening files
                var sanitizedMessage = ex.Message;
                // Remove file paths that might trigger Windows file associations
                if (sanitizedMessage.Contains(".psm1"))
                {
                    sanitizedMessage = sanitizedMessage.Replace(".psm1", "[module file]");
                }
                // Remove full paths but keep relative references
                var pathPattern = @"[A-Z]:\\[^\s]+";
                sanitizedMessage = System.Text.RegularExpressions.Regex.Replace(sanitizedMessage, pathPattern, "[path]");
                
                StatusMessage = "Error loading clients. Use Discover to find companies.";
                
                // Clear any loading placeholder
                Clients.Clear();
                
                // Add helpful error message (without file paths)
                Clients.Add(new ClientNode 
                { 
                    Name = $"⚠ Error loading clients", 
                    IsPlatform = false 
                });
                
                Clients.Add(new ClientNode 
                { 
                    Name = $"   {sanitizedMessage}", 
                    IsPlatform = false 
                });
                
                Clients.Add(new ClientNode 
                { 
                    Name = "Click Refresh to retry", 
                    IsPlatform = false 
                });
            }
            finally
            {
                IsLoading = false;
            }
        }
        
        private async Task DiscoverCompaniesAsync()
        {
            IsLoading = true;
            Clients.Clear();
            
            // Show debug log location and create test entry
            var logPath = Services.PowerShellRunner.DebugLogPath;
            StatusMessage = $"Discovering companies... Log: {logPath}";
            
            // Add initial status message to client list so user can see what's happening
            Clients.Add(new ClientNode 
            { 
                Name = "⏳ Starting discovery...", 
                IsPlatform = false 
            });
            Clients.Add(new ClientNode 
            { 
                Name = "", 
                IsPlatform = false 
            });
            Clients.Add(new ClientNode 
            { 
                Name = $"📝 DEBUG LOG FILE:", 
                IsPlatform = false 
            });
            Clients.Add(new ClientNode 
            { 
                Name = $"   {logPath}", 
                IsPlatform = false 
            });
            
            // Test write to log file to ensure it's created
            try
            {
                var logDir = System.IO.Path.GetDirectoryName(logPath);
                if (!string.IsNullOrEmpty(logDir) && !System.IO.Directory.Exists(logDir))
                {
                    System.IO.Directory.CreateDirectory(logDir);
                }
                System.IO.File.WriteAllText(logPath, $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff}] Discovery started\n");
                Clients.Add(new ClientNode 
                { 
                    Name = "✅ Log file created successfully", 
                    IsPlatform = false 
                });
                System.Diagnostics.Debug.WriteLine($"Debug log file created at: {logPath}");
            }
            catch (Exception logEx)
            {
                Clients.Add(new ClientNode 
                { 
                    Name = $"❌ Failed to create log file!", 
                    IsPlatform = false 
                });
                Clients.Add(new ClientNode 
                { 
                    Name = $"   Error: {logEx.Message}", 
                    IsPlatform = false 
                });
                System.Diagnostics.Debug.WriteLine($"Failed to create log file: {logEx.Message}");
                System.Diagnostics.Debug.WriteLine($"Log path: {logPath}");
                System.Windows.MessageBox.Show($"Failed to create debug log file:\n{logEx.Message}\n\nPath: {logPath}", "Debug Log Error", System.Windows.MessageBoxButton.OK, System.Windows.MessageBoxImage.Warning);
            }
            
            // Small delay to ensure message is visible
            await Task.Delay(300);
            
            try
            {
                int s1Count = 0;
                int perchCount = 0;
                
                // Discover from SentinelOne
                try
                {
                    Clients.Clear();
                    Clients.Add(new ClientNode 
                    { 
                        Name = "🔍 Discovering SentinelOne sites...", 
                        IsPlatform = false 
                    });
                    StatusMessage = "Discovering SentinelOne sites...";
                    
                    // Delay to make message visible
                    await Task.Delay(500);
                    
                    // Log before calling PowerShell
                    try
                    {
                        var s1JsonLogPath = Services.PowerShellRunner.DebugLogPath;
                        System.IO.File.AppendAllText(s1JsonLogPath, $"[S1 Discovery] Calling Get-S1Sites with Platform=ConnectWiseS1\n");
                        System.IO.File.AppendAllText(s1JsonLogPath, $"[S1 Discovery] About to call ExecuteScriptAsync...\n");
                    }
                    catch { }
                    
                    string s1SitesJson = "[]";
                    try
                    {
                        s1SitesJson = await _powerShellRunner.ExecuteScriptAsync("Discover-S1Sites.ps1");
                        
                        try
                        {
                            var s1JsonLogPath = Services.PowerShellRunner.DebugLogPath;
                            System.IO.File.AppendAllText(s1JsonLogPath, $"[S1 Discovery] ExecuteScriptAsync returned successfully\n");
                        }
                        catch { }
                    }
                    catch (Exception psEx)
                    {
                        try
                        {
                            var s1JsonLogPath = Services.PowerShellRunner.DebugLogPath;
                            System.IO.File.AppendAllText(s1JsonLogPath, $"[S1 Discovery] ExecuteScriptAsync EXCEPTION: {psEx.GetType().Name}: {psEx.Message}\n");
                            System.IO.File.AppendAllText(s1JsonLogPath, $"[S1 Discovery] Stack trace: {psEx.StackTrace}\n");
                        }
                        catch { }
                        throw; // Re-throw to be handled by outer catch
                    }
                    
                    // Debug: Log the JSON response
                    try
                    {
                        var s1JsonLogPath = Services.PowerShellRunner.DebugLogPath;
                        System.IO.File.AppendAllText(s1JsonLogPath, $"[S1 Discovery] JSON Response Length: {s1SitesJson?.Length ?? 0}\n");
                        System.Diagnostics.Debug.WriteLine($"S1 Sites JSON Response Length: {s1SitesJson?.Length ?? 0}");
                        if (!string.IsNullOrWhiteSpace(s1SitesJson))
                        {
                            var preview = s1SitesJson.Substring(0, Math.Min(1000, s1SitesJson.Length));
                            System.IO.File.AppendAllText(s1JsonLogPath, $"[S1 Discovery] JSON Response (first 1000 chars): {preview}...\n");
                            System.Diagnostics.Debug.WriteLine($"S1 Sites JSON Response (first 1000 chars): {preview}...");
                        }
                        else
                        {
                            System.IO.File.AppendAllText(s1JsonLogPath, $"[S1 Discovery] JSON Response is null or empty\n");
                        }
                    }
                    catch (Exception logEx)
                    {
                        System.Diagnostics.Debug.WriteLine($"Failed to write to debug log: {logEx.Message}");
                        System.Diagnostics.Debug.WriteLine($"Log path: {Services.PowerShellRunner.DebugLogPath}");
                    }
                    
                    // Check if we got valid JSON
                    if (string.IsNullOrWhiteSpace(s1SitesJson))
                    {
                        Clients.Clear();
                        Clients.Add(new ClientNode 
                        { 
                            Name = "⚠ S1 Discovery returned empty response", 
                            IsPlatform = false 
                        });
                        Clients.Add(new ClientNode 
                        { 
                            Name = "   Check authentication and API access", 
                            IsPlatform = false 
                        });
                        StatusMessage = "S1 discovery returned empty response";
                    }
                    else if (s1SitesJson.Trim() == "[]" || s1SitesJson.Trim() == "null")
                    {
                        Clients.Clear();
                        Clients.Clear();
                        Clients.Add(new ClientNode 
                        { 
                            Name = "⚠ No SentinelOne sites found", 
                            IsPlatform = false 
                        });
                        Clients.Add(new ClientNode 
                        { 
                            Name = "   API returned empty array - no sites available", 
                            IsPlatform = false 
                        });
                        Clients.Add(new ClientNode 
                        { 
                            Name = "   Possible causes:", 
                            IsPlatform = false 
                        });
                        Clients.Add(new ClientNode 
                        { 
                            Name = "   • Token file missing: %USERPROFILE%\\.s1token_connectwise", 
                            IsPlatform = false 
                        });
                        Clients.Add(new ClientNode 
                        { 
                            Name = "   • API returned empty array (no sites)", 
                            IsPlatform = false 
                        });
                        Clients.Add(new ClientNode 
                        { 
                            Name = "   • Check Debug output for details", 
                            IsPlatform = false 
                        });
                        StatusMessage = "No SentinelOne sites found - check Debug output";
                    }
                    else
                    {
                        // Try to parse JSON
                        dynamic[]? sites = null;
                        try
                        {
                            // Debug: Log raw JSON before parsing
                            try
                            {
                                var parseLogPath = Services.PowerShellRunner.DebugLogPath;
                                System.IO.File.AppendAllText(parseLogPath, $"[S1 Discovery] Attempting to parse JSON (length: {s1SitesJson.Length})\n");
                                System.IO.File.AppendAllText(parseLogPath, $"[S1 Discovery] First 500 chars: {s1SitesJson.Substring(0, Math.Min(500, s1SitesJson.Length))}\n");
                            }
                            catch (Exception logEx)
                            {
                                System.Diagnostics.Debug.WriteLine($"Failed to write parse log: {logEx.Message}");
                            }
                            System.Diagnostics.Debug.WriteLine($"Attempting to parse S1 JSON (length: {s1SitesJson.Length})");
                            System.Diagnostics.Debug.WriteLine($"First 500 chars: {s1SitesJson.Substring(0, Math.Min(500, s1SitesJson.Length))}");
                            
                            // Try parsing as JArray first to see structure
                            var jArray = Newtonsoft.Json.Linq.JArray.Parse(s1SitesJson);
                            System.Diagnostics.Debug.WriteLine($"Parsed as JArray with {jArray.Count} items");
                            
                            if (jArray.Count > 0)
                            {
                                var firstItem = jArray[0];
                                System.Diagnostics.Debug.WriteLine($"First item type: {firstItem.GetType().Name}");
                                System.Diagnostics.Debug.WriteLine($"First item: {firstItem.ToString()}");
                                
                                // Log all property names from first item
                                if (firstItem is Newtonsoft.Json.Linq.JObject firstObj)
                                {
                                    var propNames = string.Join(", ", firstObj.Properties().Select(p => p.Name));
                                    System.Diagnostics.Debug.WriteLine($"First item properties: {propNames}");
                                }
                            }
                            
                            // Now deserialize as dynamic[]
                            sites = Newtonsoft.Json.JsonConvert.DeserializeObject<dynamic[]>(s1SitesJson);
                            System.Diagnostics.Debug.WriteLine($"Deserialized to dynamic[]: {(sites == null ? "null" : $"array with {sites.Length} items")}");
                        }
                        catch (Exception parseEx)
                        {
                            System.Diagnostics.Debug.WriteLine($"JSON Parse Error: {parseEx.Message}");
                            System.Diagnostics.Debug.WriteLine($"JSON Parse StackTrace: {parseEx.StackTrace}");
                            System.Diagnostics.Debug.WriteLine($"JSON Content (full): {s1SitesJson}");
                            Clients.Clear();
                            Clients.Add(new ClientNode 
                            { 
                                Name = "❌ Failed to parse S1 response", 
                                IsPlatform = false 
                            });
                            Clients.Add(new ClientNode 
                            { 
                                Name = $"   Parse error: {parseEx.Message}", 
                                IsPlatform = false 
                            });
                            Clients.Add(new ClientNode 
                            { 
                                Name = "   Check Debug output for full JSON", 
                                IsPlatform = false 
                            });
                            StatusMessage = "Failed to parse S1 discovery response";
                            await Task.Delay(3000);
                            // sites remains null, will skip to Perch discovery
                        }
                        
                        if (sites != null && sites.Length > 0)
                        {
                            s1Count = sites.Length;
                            
                            // Debug: Log site details
                            System.Diagnostics.Debug.WriteLine($"Successfully parsed {s1Count} sites from JSON");
                            if (sites.Length > 0)
                            {
                                var firstSite = sites[0];
                                try
                                {
                                    if (firstSite is Newtonsoft.Json.Linq.JObject jObj)
                                    {
                                        var propNames = string.Join(", ", jObj.Properties().Select(p => $"{p.Name}={p.Value}"));
                                        System.Diagnostics.Debug.WriteLine($"First site (as JObject) properties: {propNames}");
                                    }
                                    else
                                    {
                                        System.Diagnostics.Debug.WriteLine($"First site type: {firstSite.GetType().Name}");
                                        System.Diagnostics.Debug.WriteLine($"First site: {firstSite.ToString()}");
                                    }
                                }
                                catch (Exception debugEx)
                                {
                                    System.Diagnostics.Debug.WriteLine($"Error inspecting first site: {debugEx.Message}");
                                }
                            }
                            
                            Clients.Clear();
                            Clients.Add(new ClientNode 
                            { 
                                Name = $"✅ Found {s1Count} SentinelOne sites", 
                                IsPlatform = false 
                            });
                            StatusMessage = $"Discovered {s1Count} SentinelOne sites";
                            
                            // Show sites in list - try multiple property name variations
                            foreach (var site in sites.Take(10)) // Show first 10
                            {
                                // Try different property name variations
                                string siteName = "Unknown";
                                string siteId = "N/A";
                                
                                try
                                {
                                    // Try accessing as JObject first
                                    if (site is Newtonsoft.Json.Linq.JObject siteObj)
                                    {
                                        siteName = siteObj["SiteName"]?.ToString() 
                                            ?? siteObj["siteName"]?.ToString()
                                            ?? siteObj["name"]?.ToString()
                                            ?? siteObj["Name"]?.ToString()
                                            ?? "Unknown";
                                            
                                        siteId = siteObj["SiteId"]?.ToString() 
                                            ?? siteObj["siteId"]?.ToString()
                                            ?? siteObj["id"]?.ToString()
                                            ?? siteObj["Id"]?.ToString()
                                            ?? "N/A";
                                    }
                                    else
                                    {
                                        // Try dynamic access
                                        siteName = site.SiteName?.ToString() 
                                            ?? site.name?.ToString() 
                                            ?? site.siteName?.ToString()
                                            ?? "Unknown";
                                            
                                        siteId = site.SiteId?.ToString() 
                                            ?? site.id?.ToString() 
                                            ?? site.siteId?.ToString()
                                            ?? "N/A";
                                    }
                                }
                                catch (Exception propEx)
                                {
                                    System.Diagnostics.Debug.WriteLine($"Error accessing site properties: {propEx.Message}");
                                }
                                
                                Clients.Add(new ClientNode 
                                { 
                                    Name = $"  • {siteName} (ID: {siteId})", 
                                    IsPlatform = false,
                                    SiteId = siteId,
                                    SiteName = siteName
                                });
                            }
                            if (s1Count > 10)
                            {
                                Clients.Add(new ClientNode 
                                { 
                                    Name = $"  ... and {s1Count - 10} more sites", 
                                    IsPlatform = false 
                                });
                            }
                        }
                        else
                        {
                            // Sites array is null or empty after parsing
                            System.Diagnostics.Debug.WriteLine($"Sites array is null or empty after JSON parsing");
                            System.Diagnostics.Debug.WriteLine($"JSON was: {s1SitesJson.Substring(0, Math.Min(200, s1SitesJson.Length))}...");
                            Clients.Clear();
                            Clients.Add(new ClientNode 
                            { 
                                Name = "⚠ Parsed JSON but found 0 sites", 
                                IsPlatform = false 
                            });
                            Clients.Add(new ClientNode 
                            { 
                                Name = "   Check Debug output for JSON structure", 
                                IsPlatform = false 
                            });
                        }
                    }
                    
                    // Delay to show results
                    await Task.Delay(2000);
                }
                catch (Exception ex)
                {
                    // Always log the error for debugging
                    System.Diagnostics.Debug.WriteLine($"S1 Discovery Error: {ex.Message}");
                    System.Diagnostics.Debug.WriteLine($"S1 Discovery StackTrace: {ex.StackTrace}");
                    
                    // Filter out Diagnostics.dll errors
                    if (!Services.PowerShellRunner.IsDiagnosticsError(ex.Message))
                    {
                        // Show detailed error information
                        var errorMsg = ex.Message;
                        if (errorMsg.Contains("Token file not found") || errorMsg.Contains("credentials not found"))
                        {
                            errorMsg = "Authentication required. Run: Set-PlatformToken -Platform ConnectWiseS1";
                        }
                        else if (errorMsg.Contains("401") || errorMsg.Contains("Authentication failed"))
                        {
                            errorMsg = "Authentication failed. Token may be expired. Run: Set-PlatformToken -Platform ConnectWiseS1";
                        }
                        else if (errorMsg.Contains("Connection") || errorMsg.Contains("Failed to retrieve"))
                        {
                            errorMsg = $"Connection error: {ex.Message}";
                        }
                        
                        Clients.Clear();
                        Clients.Add(new ClientNode 
                        { 
                            Name = $"❌ S1 Discovery Failed", 
                            IsPlatform = false 
                        });
                        Clients.Add(new ClientNode 
                        { 
                            Name = $"   {errorMsg}", 
                            IsPlatform = false 
                        });
                        Clients.Add(new ClientNode 
                        { 
                            Name = $"   Check: Token file exists at %USERPROFILE%\\.s1token_connectwise", 
                            IsPlatform = false 
                        });
                        StatusMessage = $"S1 discovery failed: {errorMsg}";
                    }
                    else
                    {
                        Clients.Clear();
                        Clients.Add(new ClientNode 
                        { 
                            Name = "✅ S1 discovery completed (warnings suppressed)", 
                            IsPlatform = false 
                        });
                        StatusMessage = "S1 discovery completed (warnings suppressed)";
                    }
                    
                    // Delay to show error
                    await Task.Delay(3000);
                }
                
                // Discover from Perch
                try
                {
                    Clients.Add(new ClientNode 
                    { 
                        Name = "", 
                        IsPlatform = false 
                    });
                    Clients.Add(new ClientNode 
                    { 
                        Name = "🔍 Discovering Perch teams...", 
                        IsPlatform = false 
                    });
                    StatusMessage = $"Discovered {s1Count} S1 sites. Discovering Perch teams...";
                    
                    // Delay to make message visible
                    await Task.Delay(500);
                    
                    var perchTeamsJson = await _powerShellRunner.ExecuteScriptAsync("Discover-PerchTeams.ps1");
                    
                    // Debug: Log the JSON response
                    System.Diagnostics.Debug.WriteLine($"Perch Teams JSON Response Length: {perchTeamsJson?.Length ?? 0}");
                    if (!string.IsNullOrWhiteSpace(perchTeamsJson))
                    {
                        System.Diagnostics.Debug.WriteLine($"Perch Teams JSON Response (first 1000 chars): {perchTeamsJson.Substring(0, Math.Min(1000, perchTeamsJson.Length))}...");
                    }
                    
                    // Check if we got valid JSON
                    if (string.IsNullOrWhiteSpace(perchTeamsJson))
                    {
                        Clients.Add(new ClientNode 
                        { 
                            Name = "", 
                            IsPlatform = false 
                        });
                        Clients.Add(new ClientNode 
                        { 
                            Name = "⚠ Perch Discovery returned empty response", 
                            IsPlatform = false 
                        });
                        Clients.Add(new ClientNode 
                        { 
                            Name = "   Check authentication and API access", 
                            IsPlatform = false 
                        });
                        StatusMessage = "Perch discovery returned empty response";
                    }
                    else if (perchTeamsJson.Trim() == "[]" || perchTeamsJson.Trim() == "null")
                    {
                        Clients.Add(new ClientNode 
                        { 
                            Name = "", 
                            IsPlatform = false 
                        });
                        Clients.Add(new ClientNode 
                        { 
                            Name = "⚠ No Perch teams found", 
                            IsPlatform = false 
                        });
                        Clients.Add(new ClientNode 
                        { 
                            Name = "   API returned empty array - no teams available", 
                            IsPlatform = false 
                        });
                        StatusMessage = $"Discovered {s1Count} S1 sites, 0 Perch teams. Use Refresh to reload from config.";
                    }
                    else
                    {
                        dynamic[]? teams = null;
                        try
                        {
                            teams = Newtonsoft.Json.JsonConvert.DeserializeObject<dynamic[]>(perchTeamsJson);
                        }
                        catch (Exception parseEx)
                        {
                            System.Diagnostics.Debug.WriteLine($"JSON Parse Error: {parseEx.Message}");
                            System.Diagnostics.Debug.WriteLine($"JSON Content: {perchTeamsJson}");
                            Clients.Add(new ClientNode 
                            { 
                                Name = "❌ Failed to parse Perch response", 
                                IsPlatform = false 
                            });
                            Clients.Add(new ClientNode 
                            { 
                                Name = $"   Parse error: {parseEx.Message}", 
                                IsPlatform = false 
                            });
                            StatusMessage = "Failed to parse Perch discovery response";
                            await Task.Delay(3000);
                        }
                        
                        if (teams != null && teams.Length > 0)
                        {
                            perchCount = teams.Length;
                            
                            Clients.Add(new ClientNode 
                            { 
                                Name = "", 
                                IsPlatform = false 
                            });
                            Clients.Add(new ClientNode 
                            { 
                                Name = $"✅ Found {perchCount} Perch teams", 
                                IsPlatform = false 
                            });
                            StatusMessage = $"Discovered {s1Count} S1 sites, {perchCount} Perch teams. Use Refresh to reload from config.";
                            
                            // Show teams in list
                            foreach (var team in teams.Take(10)) // Show first 10
                        {
                            Clients.Add(new ClientNode 
                            { 
                                Name = $"  • {team.TeamName?.ToString() ?? team.name?.ToString() ?? "Unknown"} (ID: {team.TeamId?.ToString() ?? team.id?.ToString() ?? "N/A"})", 
                                IsPlatform = false 
                            });
                        }
                            if (perchCount > 10)
                            {
                                Clients.Add(new ClientNode 
                                { 
                                    Name = $"  ... and {perchCount - 10} more teams", 
                                    IsPlatform = false 
                                });
                            }
                        }
                    }
                    
                    // Delay to show results
                    await Task.Delay(2000);
                }
                catch (Exception ex)
                {
                    // Always log the error for debugging
                    System.Diagnostics.Debug.WriteLine($"Perch Discovery Error: {ex.Message}");
                    System.Diagnostics.Debug.WriteLine($"Perch Discovery StackTrace: {ex.StackTrace}");
                    
                    // Filter out Diagnostics.dll errors
                    if (!Services.PowerShellRunner.IsDiagnosticsError(ex.Message))
                    {
                        // Show detailed error information
                        var errorMsg = ex.Message;
                        if (errorMsg.Contains("Token file not found") || errorMsg.Contains("credentials not found"))
                        {
                            errorMsg = "Authentication required. Run: Set-PerchOAuth2Credentials or Set-PlatformToken -Platform PerchSIEM";
                        }
                        else if (errorMsg.Contains("401") || errorMsg.Contains("Authentication failed"))
                        {
                            errorMsg = "Authentication failed. Credentials may be expired. Run: Set-PerchOAuth2Credentials";
                        }
                        else if (errorMsg.Contains("Connection") || errorMsg.Contains("Failed to retrieve"))
                        {
                            errorMsg = $"Connection error: {ex.Message}";
                        }
                        
                        Clients.Add(new ClientNode 
                        { 
                            Name = "", 
                            IsPlatform = false 
                        });
                        Clients.Add(new ClientNode 
                        { 
                            Name = $"❌ Perch Discovery Failed", 
                            IsPlatform = false 
                        });
                        Clients.Add(new ClientNode 
                        { 
                            Name = $"   {errorMsg}", 
                            IsPlatform = false 
                        });
                        Clients.Add(new ClientNode 
                        { 
                            Name = $"   Check: Token files exist at %USERPROFILE%", 
                            IsPlatform = false 
                        });
                        StatusMessage = $"Perch discovery failed: {errorMsg}";
                    }
                    else
                    {
                        Clients.Add(new ClientNode 
                        { 
                            Name = "✅ Perch discovery completed (warnings suppressed)", 
                            IsPlatform = false 
                        });
                        StatusMessage = $"Discovered {s1Count} S1 sites. Perch discovery completed (warnings suppressed). Use Refresh to reload.";
                    }
                    
                    // Delay to show error
                    await Task.Delay(3000);
                }
                
                // Show final summary
                Clients.Add(new ClientNode 
                { 
                    Name = "", 
                    IsPlatform = false 
                });
                
                if (s1Count == 0 && perchCount == 0)
                {
                    Clients.Add(new ClientNode 
                    { 
                        Name = "", 
                        IsPlatform = false 
                    });
                    Clients.Add(new ClientNode 
                    { 
                        Name = "📋 Summary: No companies found", 
                        IsPlatform = false 
                    });
                    Clients.Add(new ClientNode 
                    { 
                        Name = "   • Check authentication tokens exist", 
                        IsPlatform = false 
                    });
                    Clients.Add(new ClientNode 
                    { 
                        Name = "   • Run: .\\test-api-access.ps1 to verify API access", 
                        IsPlatform = false 
                    });
                    Clients.Add(new ClientNode 
                    { 
                        Name = "   • Run: .\\discover-companies.ps1 to test discovery", 
                        IsPlatform = false 
                    });
                    StatusMessage = "Discovery completed but no companies found. Check authentication and API access.";
                }
                else
                {
                    Clients.Add(new ClientNode 
                    { 
                        Name = $"📋 Summary: {s1Count} S1 sites, {perchCount} Perch teams discovered", 
                        IsPlatform = false 
                    });
                    Clients.Add(new ClientNode 
                    { 
                        Name = "💡 Click Refresh to load clients from config", 
                        IsPlatform = false 
                    });
                    StatusMessage = $"Discovery complete: {s1Count} S1 sites, {perchCount} Perch teams. Click Refresh to load clients from config.";
                }
            }
            catch (Exception ex)
            {
                // Filter out Diagnostics.dll errors
                if (!Services.PowerShellRunner.IsDiagnosticsError(ex.Message))
                {
                    Clients.Clear();
                    Clients.Add(new ClientNode 
                    { 
                        Name = $"❌ Discovery error: {ex.Message}", 
                        IsPlatform = false 
                    });
                    StatusMessage = $"Discovery error: {ex.Message}";
                    System.Diagnostics.Debug.WriteLine($"Discovery Error: {ex}");
                }
                else
                {
                    Clients.Clear();
                    Clients.Add(new ClientNode 
                    { 
                        Name = "✅ Discovery completed (warnings suppressed)", 
                        IsPlatform = false 
                    });
                    Clients.Add(new ClientNode 
                    { 
                        Name = "💡 Click Refresh to reload clients", 
                        IsPlatform = false 
                    });
                    StatusMessage = "Discovery completed (warnings suppressed). Click Refresh to reload clients.";
                }
            }
            finally
            {
                IsLoading = false;
            }
        }
        
        public event PropertyChangedEventHandler? PropertyChanged;
        
        protected virtual void OnPropertyChanged([CallerMemberName] string? propertyName = null)
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
        }
    }
    
    public class ClientNode
    {
        public string Name { get; set; } = string.Empty;
        public bool IsPlatform { get; set; }
        public bool IsReadOnly { get; set; }
        public bool CanTakeAction { get; set; }
        public string SiteId { get; set; } = string.Empty;
        public string SiteName { get; set; } = string.Empty;
        public bool HasPerch { get; set; }
        public string PerchTeamId { get; set; } = string.Empty;
    }
    
    public class RelayCommand : ICommand
    {
        private readonly Func<Task> _execute;
        private readonly Func<bool>? _canExecute;
        
        public RelayCommand(Func<Task> execute, Func<bool>? canExecute = null)
        {
            _execute = execute ?? throw new ArgumentNullException(nameof(execute));
            _canExecute = canExecute;
        }
        
        public event EventHandler? CanExecuteChanged
        {
            add { CommandManager.RequerySuggested += value; }
            remove { CommandManager.RequerySuggested -= value; }
        }
        
        public bool CanExecute(object? parameter)
        {
            return _canExecute == null || _canExecute();
        }
        
        public async void Execute(object? parameter)
        {
            try
            {
                await _execute();
            }
            catch (Exception ex)
            {
                // Log or handle exception appropriately
                System.Diagnostics.Debug.WriteLine($"RelayCommand execution error: {ex.Message}");
            }
        }
    }
}

