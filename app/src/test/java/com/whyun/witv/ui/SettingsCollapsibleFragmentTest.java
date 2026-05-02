package com.whyun.witv.ui;

import android.view.View;
import android.widget.FrameLayout;

import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.shadows.ShadowLooper;

import java.lang.reflect.Field;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;

@RunWith(RobolectricTestRunner.class)
public class SettingsCollapsibleFragmentTest {

    @Test
    public void onMainMenuItemFocusedCancelsPendingOpenWhenReturningToOpenCategory()
            throws Exception {
        SettingsCollapsibleFragment fragment = new SettingsCollapsibleFragment();
        FrameLayout submenuContainer = new FrameLayout(
                androidx.test.core.app.ApplicationProvider.getApplicationContext());
        submenuContainer.setVisibility(View.VISIBLE);

        setField(fragment, "submenuContainer", submenuContainer);
        setField(fragment, "openCategory", SettingsCollapsibleFragment.CAT_ADDRESS);

        fragment.onMainMenuItemFocused(SettingsCollapsibleFragment.CAT_EPG);
        fragment.onMainMenuItemFocused(SettingsCollapsibleFragment.CAT_ADDRESS);

        ShadowLooper.runUiThreadTasksIncludingDelayedTasks();

        assertNull(getField(fragment, "pendingSubmenuOpen"));
        assertEquals(SettingsCollapsibleFragment.CAT_ADDRESS, getField(fragment, "openCategory"));
    }

    private static void setField(Object target, String fieldName, Object value) throws Exception {
        Field field = target.getClass().getDeclaredField(fieldName);
        field.setAccessible(true);
        field.set(target, value);
    }

    private static Object getField(Object target, String fieldName) throws Exception {
        Field field = target.getClass().getDeclaredField(fieldName);
        field.setAccessible(true);
        return field.get(target);
    }
}
