using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace RiverRunThreatHunter.ViewModels
{
    public class IOCInputViewModel : INotifyPropertyChanged
    {
        private string _iocText = "";
        
        public string IOCText
        {
            get => _iocText;
            set
            {
                _iocText = value;
                OnPropertyChanged();
            }
        }
        
        public ObservableCollection<IOC> IOCs { get; set; } = new ObservableCollection<IOC>();
        
        public event PropertyChangedEventHandler? PropertyChanged;
        
        protected virtual void OnPropertyChanged([CallerMemberName] string? propertyName = null)
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
        }
    }
    
    public class IOC
    {
        public string Type { get; set; } = string.Empty;
        public string Value { get; set; } = string.Empty;
    }
}

