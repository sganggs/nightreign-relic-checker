package com.nightreign.relicchecker

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.nightreign.relicchecker.ui.NightreignApp
import com.nightreign.relicchecker.ui.theme.NightreignTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            NightreignTheme {
                NightreignApp()
            }
        }
    }
}
