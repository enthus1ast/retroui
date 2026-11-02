package org.retro;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import android.provider.OpenableColumns;
import java.io.File;
import java.io.FileNotFoundException;

/** Hands files to other apps for viewing and sharing: content://<app>.files/
 *  followed by the file's path. Read only, and only to the apps a
 *  RetroActivity.openFile intent grants it to (not exported). */
public class RetroFiles extends ContentProvider {
  @Override
  public boolean onCreate() {
    return true;
  }

  private static File fileOf(Uri uri) {
    return new File(uri.getPath());
  }

  @Override
  public ParcelFileDescriptor openFile(Uri uri, String mode) throws FileNotFoundException {
    return ParcelFileDescriptor.open(fileOf(uri), ParcelFileDescriptor.MODE_READ_ONLY);
  }

  @Override
  public String getType(Uri uri) {
    return RetroActivity.mimeOf(uri.getPath());
  }

  @Override
  public Cursor query(Uri uri, String[] projection, String selection, String[] args,
                      String order) {
    File f = fileOf(uri);
    String[] cols = projection != null ? projection
        : new String[] {OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE};
    MatrixCursor c = new MatrixCursor(cols, 1);
    Object[] row = new Object[cols.length];
    for (int i = 0; i < cols.length; i++) {
      if (OpenableColumns.DISPLAY_NAME.equals(cols[i])) row[i] = f.getName();
      else if (OpenableColumns.SIZE.equals(cols[i])) row[i] = f.length();
    }
    c.addRow(row);
    return c;
  }

  @Override
  public Uri insert(Uri uri, ContentValues values) {
    return null;
  }

  @Override
  public int delete(Uri uri, String selection, String[] args) {
    return 0;
  }

  @Override
  public int update(Uri uri, ContentValues values, String selection, String[] args) {
    return 0;
  }
}
