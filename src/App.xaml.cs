using System;
using System.Windows;
using System.Windows.Threading;
using RiverRunThreatHunter.Services;

namespace RiverRunThreatHunter
{
    public partial class App : Application
    {
        protected override void OnStartup(StartupEventArgs e)
        {
            base.OnStartup(e);
            
            // Handle unhandled exceptions
            this.DispatcherUnhandledException += App_DispatcherUnhandledException;
            AppDomain.CurrentDomain.UnhandledException += CurrentDomain_UnhandledException;
        }
        
        private void App_DispatcherUnhandledException(object sender, DispatcherUnhandledExceptionEventArgs e)
        {
            // Filter out Diagnostics.dll errors - don't show them to the user
            if (PowerShellRunner.IsDiagnosticsError(e.Exception.Message))
            {
                e.Handled = true;
                return;
            }
            
            MessageBox.Show(
                $"An error occurred: {e.Exception.Message}\n\n{e.Exception.StackTrace}",
                "Error",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
            e.Handled = true;
        }
        
        private void CurrentDomain_UnhandledException(object sender, UnhandledExceptionEventArgs e)
        {
            if (e.ExceptionObject is Exception ex)
            {
                // Filter out Diagnostics.dll errors - don't show them to the user
                if (PowerShellRunner.IsDiagnosticsError(ex.Message))
                {
                    return;
                }
                
                MessageBox.Show(
                    $"An unhandled error occurred: {ex.Message}\n\n{ex.StackTrace}",
                    "Fatal Error",
                    MessageBoxButton.OK,
                    MessageBoxImage.Error);
            }
        }
    }
}

