using System.Windows;
using System.Windows.Controls;
using Microsoft.Win32;
using RiverRunThreatHunter.ViewModels;

namespace RiverRunThreatHunter.Views
{
    public partial class IOCInputPanel : UserControl
    {
        public IOCInputViewModel? ViewModel => DataContext as IOCInputViewModel;
        
        public IOCInputPanel()
        {
            InitializeComponent();
            if (DataContext == null)
            {
                DataContext = new IOCInputViewModel();
            }
        }
        
        private void PasteButton_Click(object sender, RoutedEventArgs e)
        {
            IOCTextBox.Paste();
            if (ViewModel != null)
            {
                ViewModel.IOCText = IOCTextBox.Text;
            }
        }
        
        private void ImportCsvButton_Click(object sender, RoutedEventArgs e)
        {
            var dialog = new OpenFileDialog
            {
                Filter = "CSV files (*.csv)|*.csv|All files (*.*)|*.*",
                Title = "Import IOCs from CSV"
            };
            
            if (dialog.ShowDialog() == true)
            {
                // TODO: Implement CSV import
                MessageBox.Show("CSV import not yet implemented", "Info", MessageBoxButton.OK, MessageBoxImage.Information);
            }
        }
        
        private void TicketButton_Click(object sender, RoutedEventArgs e)
        {
            // TODO: Implement ticket import
            MessageBox.Show("Ticket import not yet implemented", "Info", MessageBoxButton.OK, MessageBoxImage.Information);
        }
        
        private void MemberberryButton_Click(object sender, RoutedEventArgs e)
        {
            // TODO: Implement Memberberry import
            MessageBox.Show("Memberberry import not yet implemented", "Info", MessageBoxButton.OK, MessageBoxImage.Information);
        }
    }
}

