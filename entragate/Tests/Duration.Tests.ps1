BeforeAll {
    . "$PSScriptRoot/../Private/Duration.ps1"
}

Describe 'ConvertTo-IsoDuration' {

    Context 'Minutes only' {
        It 'Bare tall tolkes som minutter' {
            ConvertTo-IsoDuration '30'   | Should -Be 'PT30M'
            ConvertTo-IsoDuration '90'   | Should -Be 'PT1H30M'
            ConvertTo-IsoDuration '60'   | Should -Be 'PT1H'
        }
        It 'Eksplisitt m-suffix' {
            ConvertTo-IsoDuration '30m'  | Should -Be 'PT30M'
            ConvertTo-IsoDuration '90m'  | Should -Be 'PT1H30M'
        }
    }

    Context 'Hours' {
        It 'Heltall timer' {
            ConvertTo-IsoDuration '1h'   | Should -Be 'PT1H'
            ConvertTo-IsoDuration '2h'   | Should -Be 'PT2H'
        }
        It 'Desimaltimer med punktum' {
            ConvertTo-IsoDuration '0.5h' | Should -Be 'PT30M'
            ConvertTo-IsoDuration '1.5h' | Should -Be 'PT1H30M'
        }
        It 'Desimaltimer med komma' {
            ConvertTo-IsoDuration '0,5h' | Should -Be 'PT30M'
            ConvertTo-IsoDuration '1,5h' | Should -Be 'PT1H30M'
        }
    }

    Context 'Hours and minutes combined' {
        It 'Timer og minutter' {
            ConvertTo-IsoDuration '1h30m' | Should -Be 'PT1H30M'
            ConvertTo-IsoDuration '2h15m' | Should -Be 'PT2H15M'
        }
    }

    Context 'Days' {
        It 'Dagformat' {
            ConvertTo-IsoDuration '1d'   | Should -Be 'P1D'
            ConvertTo-IsoDuration '7d'   | Should -Be 'P7D'
        }
    }

    Context 'HH:MM format' {
        It 'Kolon-format' {
            ConvertTo-IsoDuration '01:30' | Should -Be 'PT1H30M'
            ConvertTo-IsoDuration '02:00' | Should -Be 'PT2H'
        }
    }

    Context 'Already ISO' {
        It 'Passerer gjennom eksisterende ISO-strenger' {
            ConvertTo-IsoDuration 'PT1H'    | Should -Be 'PT1H'
            ConvertTo-IsoDuration 'PT30M'   | Should -Be 'PT30M'
            ConvertTo-IsoDuration 'PT1H30M' | Should -Be 'PT1H30M'
        }
    }

    Context 'Invalid input' {
        It 'Kaster feil ved ugyldig input' {
            { ConvertTo-IsoDuration 'ugyldig' } | Should -Throw
        }
    }
}

Describe 'Get-MinFromIso' {

    It 'Timer til minutter' {
        Get-MinFromIso 'PT1H'    | Should -Be 60
        Get-MinFromIso 'PT2H'    | Should -Be 120
    }
    It 'Minutter' {
        Get-MinFromIso 'PT30M'   | Should -Be 30
    }
    It 'Timer og minutter' {
        Get-MinFromIso 'PT1H30M' | Should -Be 90
    }
    It 'Dager' {
        Get-MinFromIso 'P1D'     | Should -Be 1440
    }
    It 'Tom streng gir 0' {
        Get-MinFromIso ''        | Should -Be 0
        Get-MinFromIso $null     | Should -Be 0
    }
}
