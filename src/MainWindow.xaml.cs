using System.Windows;
using RiverRunThreatHunter.ViewModels;

namespace RiverRunThreatHunter
{
    public partial class MainWindow : Window
    {
        public MainViewModel ViewModel { get; set; }
        
        public MainWindow()
        {
            InitializeComponent();
            ViewModel = new MainViewModel();
            DataContext = ViewModel;
        }
        
        private void SettingsButton_Click(object sender, RoutedEventArgs e)
        {
            MessageBox.Show("Settings window not yet implemented", "Settings", MessageBoxButton.OK, MessageBoxImage.Information);
        }
        
        private void StartHuntButton_Click(object sender, RoutedEventArgs e)
        {
            MessageBox.Show("Hunt execution not yet implemented", "Start Hunt", MessageBoxButton.OK, MessageBoxImage.Information);
        }
    }
}

