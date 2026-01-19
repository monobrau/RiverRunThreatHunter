using System.ComponentModel;
using System.Runtime.CompilerServices;
using RiverRunThreatHunter.ViewModels;

namespace RiverRunThreatHunter.ViewModels
{
    public class MainViewModel : INotifyPropertyChanged
    {
        private string _statusMessage = "Ready";
        
        public ClientListViewModel ClientTreeViewModel { get; set; }
        public IOCInputViewModel IOCInputViewModel { get; set; }
        public ResultsViewModel ResultsViewModel { get; set; }
        
        public string StatusMessage
        {
            get => _statusMessage;
            set
            {
                _statusMessage = value;
                OnPropertyChanged();
            }
        }
        
        public MainViewModel()
        {
            ClientTreeViewModel = new ClientListViewModel();
            IOCInputViewModel = new IOCInputViewModel();
            ResultsViewModel = new ResultsViewModel();
        }
        
        public event PropertyChangedEventHandler? PropertyChanged;
        
        protected virtual void OnPropertyChanged([CallerMemberName] string? propertyName = null)
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
        }
    }
}

