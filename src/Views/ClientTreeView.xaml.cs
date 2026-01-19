using System;
using System.Globalization;
using System.Linq;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Input;
using RiverRunThreatHunter.ViewModels;

namespace RiverRunThreatHunter.Views
{
    public partial class ClientTreeView : UserControl
    {
        public ClientTreeView()
        {
            InitializeComponent();
        }
        
        private void CopyMenuItem_Click(object sender, RoutedEventArgs e)
        {
            CopySelectedItem();
        }
        
        private void CopyAllMenuItem_Click(object sender, RoutedEventArgs e)
        {
            CopyAllItems();
        }
        
        private void ClientList_KeyDown(object sender, KeyEventArgs e)
        {
            if (e.Key == Key.C && (Keyboard.Modifiers & ModifierKeys.Control) == ModifierKeys.Control)
            {
                CopySelectedItem();
                e.Handled = true;
            }
        }
        
        private void TextBox_SelectionChanged(object sender, RoutedEventArgs e)
        {
            // Allow text selection in TextBox
            if (sender is TextBox textBox && textBox.SelectionLength > 0)
            {
                Clipboard.SetText(textBox.SelectedText);
            }
        }
        
        private void CopySelectedItem()
        {
            if (ClientList.SelectedItem is ClientNode selectedNode)
            {
                var text = BuildClientNodeText(selectedNode);
                Clipboard.SetText(text);
            }
            else if (ClientList.SelectedItem != null)
            {
                // Fallback: try to get text from selected item
                Clipboard.SetText(ClientList.SelectedItem.ToString() ?? "");
            }
        }
        
        private void CopyAllItems()
        {
            if (DataContext is ClientListViewModel viewModel && viewModel.Clients != null)
            {
                var sb = new StringBuilder();
                foreach (var client in viewModel.Clients)
                {
                    sb.AppendLine(BuildClientNodeText(client));
                }
                Clipboard.SetText(sb.ToString());
            }
        }
        
        private string BuildClientNodeText(ClientNode node)
        {
            var sb = new StringBuilder();
            sb.Append(node.Name ?? "");
            
            if (node.IsReadOnly)
            {
                sb.Append(" (Read-Only)");
            }
            
            if (node.CanTakeAction)
            {
                sb.Append(" ✓");
            }
            
            if (node.HasPerch)
            {
                sb.Append(" 🟢");
            }
            
            if (!string.IsNullOrEmpty(node.SiteId))
            {
                sb.Append($" [SiteId: {node.SiteId}]");
            }
            
            if (!string.IsNullOrEmpty(node.SiteName))
            {
                sb.Append($" [Site: {node.SiteName}]");
            }
            
            if (!string.IsNullOrEmpty(node.PerchTeamId))
            {
                sb.Append($" [PerchTeamId: {node.PerchTeamId}]");
            }
            
            return sb.ToString();
        }
    }
    
    public class BoolToBoldConverter : IValueConverter
    {
        public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
        {
            if (value is bool isPlatform && isPlatform)
                return FontWeights.Bold;
            return FontWeights.Normal;
        }
        
        public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        {
            throw new NotImplementedException();
        }
    }
    
    public class BoolToVisibilityConverter : IValueConverter
    {
        public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
        {
            if (value is bool boolValue && boolValue)
                return System.Windows.Visibility.Visible;
            return System.Windows.Visibility.Collapsed;
        }
        
        public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        {
            throw new NotImplementedException();
        }
    }
}

