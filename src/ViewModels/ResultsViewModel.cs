using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace RiverRunThreatHunter.ViewModels
{
    public class ResultsViewModel : INotifyPropertyChanged
    {
        private ObservableCollection<HuntResult> _results = new ObservableCollection<HuntResult>();
        
        public ObservableCollection<HuntResult> Results
        {
            get => _results;
            set
            {
                _results = value;
                OnPropertyChanged();
            }
        }
        
        public event PropertyChangedEventHandler? PropertyChanged;
        
        protected virtual void OnPropertyChanged([CallerMemberName] string? propertyName = null)
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
        }
    }
    
    public class HuntResult
    {
        public string Client { get; set; } = string.Empty;
        public string Source { get; set; } = string.Empty;
        public string IOC { get; set; } = string.Empty;
        public string IOCType { get; set; } = string.Empty;
        public string Timestamp { get; set; } = string.Empty;
        public string Endpoint { get; set; } = string.Empty;
        public bool CanTakeAction { get; set; }
    }
}

